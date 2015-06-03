#import "TTStandardVersionComparator.h"

#define EXPORT extern "C" __attribute__((visibility("default")))

#define TOTALTERMINAL_STANDARD_INSTALL_LOCATION "/Applications/TotalTerminal.app"
#define TERMINAL_MIN_TESTED_VERSION @"0"
#define TERMINAL_MAX_TESTED_VERSION @"343.7"  // 10.10.4 (14E26a)
#define TERMINAL_UNSUPPORTED_VERSION @""
#define TOTALTERMINAL_INJECTED_NOTIFICATION @"TotalTerminalInjectedNotification"
#define TOTALTERMINAL_FAILED_INJECTION_NOTIFICATION @"TotalTerminalFailedInjectionNotification"

static NSString* globalLock = @"I'm the global lock to prevent concruent handler executions";
static bool alreadyLoaded = false;
static Class gPrincipalClass = nil;

@interface TotalTerminal : NSObject {
}
- (BOOL)isHidden;
- (void)showVisor:(BOOL)fast;
- (void)hideVisor:(BOOL)fast;
@end

// SIMBL-compatible interface
@interface TotalTerminalPlugin : NSObject
+ (void)install;
+ (TotalTerminal*) sharedInstance;
@end

// just a dummy class for locating our bundle
@interface TotalTerminalInjector : NSObject
@end
@implementation TotalTerminalInjector
@end

static void broadcastNotification(NSString* notification) {
  pid_t pid = [[NSProcessInfo processInfo] processIdentifier];

  [[NSDistributedNotificationCenter defaultCenter] postNotificationName:notification
                                                                 object:[[NSBundle mainBundle] bundleIdentifier]
                                                               userInfo:@{@"pid" : @(pid)}
                                                     deliverImmediately:YES];
}

static void broadcastSucessfulInjection() { broadcastNotification(TOTALTERMINAL_INJECTED_NOTIFICATION); }

static void broadcastUnsucessfulInjection() { broadcastNotification(TOTALTERMINAL_FAILED_INJECTION_NOTIFICATION); }

static OSErr AEPutParamString(AppleEvent* event, AEKeyword keyword, NSString* string) {
  UInt8* textBuf;
  CFIndex length, maxBytes, actualBytes;
  length = CFStringGetLength((CFStringRef)string);
  maxBytes = CFStringGetMaximumSizeForEncoding(length, kCFStringEncodingUTF8);
  textBuf = (UInt8*)malloc(maxBytes);
  if (textBuf) {
    CFStringGetBytes((CFStringRef)string, CFRangeMake(0, length), kCFStringEncodingUTF8, 0, true, (UInt8*)textBuf, maxBytes, &actualBytes);
    OSErr err = AEPutParamPtr(event, keyword, typeUTF8Text, textBuf, actualBytes);
    free(textBuf);
    return err;
  } else {
    return memFullErr;
  }
}

static void reportError(AppleEvent* reply, NSString* msg) {
  NSLog(@"TotalTerminalInjector: %@", msg);
  AEPutParamString(reply, keyErrorString, msg);
}

static void returnBool(AppleEvent* reply, BOOL value, AEKeyword keyword = keyDirectObject) {
  AEPutParamDesc(reply, keyword, [[NSAppleEventDescriptor descriptorWithBoolean:value] aeDesc]);
}

// this is just a sanity checking to catch missing methods early
static int performSelfCheck() {
  if (!gPrincipalClass) {
    return 1;
  }
  
  if (![gPrincipalClass respondsToSelector:@selector(sharedInstance)]) {
    return 2;
  }
  
  TotalTerminal* instance = [gPrincipalClass sharedInstance];
  if (!instance) {
    return 3;
  }
  
  if (![instance respondsToSelector:@selector(isHidden)]) {
    return 4;
  }

  if (![instance respondsToSelector:@selector(showVisor:)]) {
    return 5;
  }

  if (![instance respondsToSelector:@selector(hideVisor:)]) {
    return 6;
  }
 
  return 0;
}

EXPORT OSErr handleInitEvent(const AppleEvent* ev, AppleEvent* reply, long refcon) {
  @synchronized(globalLock) {
    @autoreleasepool {
      NSBundle* injectorBundle = [NSBundle bundleForClass:[TotalTerminalInjector class]];
      NSString* injectorVersion = [injectorBundle objectForInfoDictionaryKey:@"CFBundleVersion"];
      if (!injectorVersion || ![injectorVersion isKindOfClass:[NSString class]]) {
        reportError(reply, [NSString stringWithFormat:@"Unable to determine TotalTerminalInjector version!"]);
        return 7;
      }

      NSLog(@"TotalTerminalInjector v%@ received init event", injectorVersion);

      NSString* bundleName = @"TotalTerminal";
      NSString* targetAppName = @"Terminal";
      NSString* maxVersion = TERMINAL_MAX_TESTED_VERSION;
      NSString* minVersion = TERMINAL_MIN_TESTED_VERSION;

      if (alreadyLoaded) {
        NSLog(@"TotalTerminalInjector: TotalTerminal has been already loaded. Ignoring this request.");
        return noErr;
      }
      @try {
        NSBundle* terminalBundle = [NSBundle mainBundle];
        if (!terminalBundle) {
          reportError(reply, [NSString stringWithFormat:@"Unable to locate main Terminal bundle!"]);
          return 4;
        }

        NSString* terminalVersion = [terminalBundle objectForInfoDictionaryKey:@"CFBundleVersion"];
        if (!terminalVersion || ![terminalVersion isKindOfClass:[NSString class]]) {
          reportError(reply, [NSString stringWithFormat:@"Unable to determine Terminal version!"]);
          return 5;
        }

        // some versions are explicitely unsupported
        if (([TERMINAL_UNSUPPORTED_VERSION length] > 0) && ([terminalVersion rangeOfString:TERMINAL_UNSUPPORTED_VERSION].length > 0)) {
          NSUserNotification* notification = [[NSUserNotification alloc] init];
          notification.title = [NSString stringWithFormat:@"TotalTerminal hasn't been tested with Terminal version %@", terminalVersion];
          notification.informativeText = [NSString stringWithFormat:@"Please visit http://totalterminal.binaryage.com for more info on our progress."];
          [[NSUserNotificationCenter defaultUserNotificationCenter] deliverNotification:notification];
        }

        // warn about non-tested minor versions into the log only
        NSString* supressKey = @"TotalTerminalSuppressTerminalVersionCheck";
        if (![[NSUserDefaults standardUserDefaults] boolForKey:supressKey]) {
          TTStandardVersionComparator* comparator = [TTStandardVersionComparator defaultComparator];
          if (([comparator compareVersion:terminalVersion toVersion:maxVersion] == NSOrderedDescending) ||
              ([comparator compareVersion:terminalVersion toVersion:minVersion] == NSOrderedAscending)) {
            NSLog(@"You have %@ version %@. But %@ was properly tested only with %@ versions in range %@ - %@.",
                  targetAppName,
                  terminalVersion,
                  bundleName,
                  targetAppName,
                  minVersion,
                  maxVersion);
          }
        }

        NSBundle* totalTerminalInjectorBundle = [NSBundle bundleForClass:[TotalTerminalInjector class]];
        NSString* totalTerminalLocation = [totalTerminalInjectorBundle pathForResource:bundleName ofType:@"bundle"];
        NSBundle* pluginBundle = [NSBundle bundleWithPath:totalTerminalLocation];
        if (!pluginBundle) {
          reportError(reply, [NSString stringWithFormat:@"Unable to create bundle from path: %@ [%@]", totalTerminalLocation, totalTerminalInjectorBundle]);
          return 2;
        }

        NSLog(@"TotalTerminalInjector: Installing %@ from %@", bundleName, totalTerminalLocation);
        NSError* error;
        if (![pluginBundle loadAndReturnError:&error]) {
          reportError(reply, [NSString stringWithFormat:@"Unable to load bundle from path: %@ error: %@ [code=%ld]", totalTerminalLocation, [error localizedDescription], (long)[error code]]);
          return 6;
        }

        gPrincipalClass = [pluginBundle principalClass];
        if (!gPrincipalClass) {
          reportError(reply, [NSString stringWithFormat:@"Unable to retrieve principalClass for bundle: %@", pluginBundle]);
          return 3;
        }
        
        if (![gPrincipalClass respondsToSelector:@selector(install)]) {
          reportError(reply, [NSString stringWithFormat:@"TotalTerminal's principal class does not implement 'install' method!"]);
          return 7;
        }

        [gPrincipalClass install];
        
        int selfCheckCode = performSelfCheck();
        if (selfCheckCode) {
          reportError(reply, [NSString stringWithFormat:@"Self-check failed with code %d", selfCheckCode]);
          return 10;
        }

        alreadyLoaded = true;
        broadcastSucessfulInjection();

        return noErr;
      }
      @catch (NSException* exception) {
        reportError(reply, [NSString stringWithFormat:@"Failed to load %@ with exception: %@", bundleName, exception]);
        broadcastUnsucessfulInjection();  // stops subsequent attempts
      }
      return 1;
    }
  }
}

EXPORT OSErr handleCheckEvent(const AppleEvent* ev, AppleEvent* reply, long refcon) {
  @synchronized(globalLock) {
    @autoreleasepool {
      if (alreadyLoaded) {
        return noErr;
      }
      reportError(reply, @"TotalTerminal not loaded");
      return 1;
    }
  }
}

typedef OSErr(^commandBlock)(TotalTerminal* totalTerminal);

OSErr executeCommand(commandBlock command, const AppleEvent* ev, AppleEvent* reply, long refcon) {
  @synchronized(globalLock) {
    @autoreleasepool {
      if (!gPrincipalClass) {
        reportError(reply, [NSString stringWithFormat:@"TotalTerminal not present"]);
        return 150;
      }
      
      TotalTerminal* instance = [gPrincipalClass sharedInstance];
      if (!instance) {
        reportError(reply, [NSString stringWithFormat:@"Unable to retrieve TotalTerminal instance"]);
        return 151;
      }
      
      return command(instance);
    }
  }
}

EXPORT OSErr handleShowVisorEvent(const AppleEvent* ev, AppleEvent* reply, long refcon) {
  commandBlock command = ^OSErr(TotalTerminal* totalTerminal) {
    [totalTerminal showVisor:NO];
    return noErr;
  };
  
  return executeCommand(command, ev, reply, refcon);
}

EXPORT OSErr handleHideVisorEvent(const AppleEvent* ev, AppleEvent* reply, long refcon) {
  commandBlock command = ^OSErr(TotalTerminal* totalTerminal) {
    [totalTerminal hideVisor:NO];
    return noErr;
  };
  
  return executeCommand(command, ev, reply, refcon);
}

EXPORT OSErr handleVisorHiddenEvent(const AppleEvent* ev, AppleEvent* reply, long refcon) {
  commandBlock command = ^OSErr(TotalTerminal* totalTerminal) {
    BOOL answer = [totalTerminal isHidden];
    returnBool(reply, answer);
    return noErr;
  };
  
  return executeCommand(command, ev, reply, refcon);
}