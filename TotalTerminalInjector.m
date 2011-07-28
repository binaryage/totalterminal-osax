#import <Cocoa/Cocoa.h>

#import "TFStandardVersionComparator.h"

#define TOTALTERMINAL_STANDARD_INSTALL_LOCATION "/Applications/TotalTerminal.app"
#define TERMINAL_MIN_TESTED_VERSION @"0"
#define TERMINAL_MAX_TESTED_VERSION @"297"

// SIMBL-compatible interface
@interface TotalTerminalPlugin: NSObject { 
}
- (void) install;
@end

// just a dummy class for locating our bundle
@interface TotalTerminalInjector: NSObject { 
}
@end

@implementation TotalTerminalInjector {
}
@end

static bool alreadyLoaded = false;

OSErr AEPutParamString(AppleEvent *event, AEKeyword keyword, NSString* string) {
    UInt8 *textBuf;
    CFIndex length, maxBytes, actualBytes;
    length = CFStringGetLength((CFStringRef)string);
    maxBytes = CFStringGetMaximumSizeForEncoding(length, kCFStringEncodingUTF8);
    textBuf = malloc(maxBytes);
    if (textBuf) {
        CFStringGetBytes((CFStringRef)string, CFRangeMake(0, length), kCFStringEncodingUTF8, 0, true, (UInt8 *)textBuf, maxBytes, &actualBytes);
        OSErr err = AEPutParamPtr(event, keyword, typeUTF8Text, textBuf, actualBytes);
        free(textBuf);
        return err;
    } else {
        return memFullErr;
    }
}

static void reportError(AppleEvent *reply, NSString* msg) {
    NSLog(@"TotalTerminalInjector: %@", msg);
    AEPutParamString(reply, keyErrorString, msg);
}

OSErr HandleInitEvent(const AppleEvent *ev, AppleEvent *reply, long refcon) {
    NSLog(@"TotalTerminalInjector: Received init event");
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
        if (!terminalVersion) {
            reportError(reply, [NSString stringWithFormat:@"Unable to determine Terminal version!"]);
            return 5;
        }
        
        // future compatibility check
        NSString* supressKey = @"TotalTerminalSuppressTerminalVersionCheck";
        NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
        if (![defaults boolForKey:supressKey]) {
            TFStandardVersionComparator* comparator = [TFStandardVersionComparator defaultComparator];
            if (([comparator compareVersion:terminalVersion toVersion:TERMINAL_MAX_TESTED_VERSION]==NSOrderedDescending) || 
                ([comparator compareVersion:terminalVersion toVersion:TERMINAL_MIN_TESTED_VERSION]==NSOrderedAscending)) {

                NSAlert* alert = [NSAlert new];
                [alert setMessageText: [NSString stringWithFormat:@"You have Terminal version %@", terminalVersion]];
                [alert setInformativeText: [NSString stringWithFormat:@"But TotalTerminal was properly tested only with Terminal versions in range %@ - %@\n\nYou have probably updated your system and Terminal version got bumped by Apple developers.\n\nYou may expect a new TotalTerminal release soon.", TERMINAL_MIN_TESTED_VERSION, TERMINAL_MAX_TESTED_VERSION]];
                [alert setShowsSuppressionButton:YES];
                [alert addButtonWithTitle:@"Launch TotalTerminal anyway"];
                [alert addButtonWithTitle:@"Cancel"];
                NSInteger res = [alert runModal];
                if ([[alert suppressionButton] state] == NSOnState) {
                    [defaults setBool:YES forKey:supressKey];
                }
                if (res!=NSAlertFirstButtonReturn) { // cancel
                    return noErr;
                }
            }
        }
        
        NSString* totalTerminalLocation = [[NSBundle bundleForClass:[TotalTerminalInjector class]] pathForResource:@"TotalTerminal" ofType:@"bundle"];
        NSBundle* pluginBundle = [NSBundle bundleWithPath:totalTerminalLocation];
        if (!pluginBundle) {
            reportError(reply, [NSString stringWithFormat:@"Unable to create bundle from path: %@", totalTerminalLocation]);
            return 2;
        }
        
        NSError* error;
        if (![pluginBundle loadAndReturnError:&error]) {
            reportError(reply, [NSString stringWithFormat:@"Unable to load bundle from path: %@ error: %@", totalTerminalLocation, [error localizedDescription]]);
            return 6;
        }
        
        TotalTerminalPlugin* principalClass = (TotalTerminalPlugin*)[pluginBundle principalClass];
        if (!principalClass) {
            reportError(reply, [NSString stringWithFormat:@"Unable to retrieve principalClass for bundle: %@", pluginBundle]);
            return 3;
        }
        if ([principalClass respondsToSelector:@selector(install)]) {
            NSLog(@"TotalTerminalInjector: Installing TotalTerminal ...");
            [principalClass install];
        }
        alreadyLoaded = true;
        return noErr;
    } @catch (NSException* exception) {
        reportError(reply, [NSString stringWithFormat:@"Failed to load TotalTerminal with exception: %@", exception]);
    }
    return 1;
}

OSErr HandleCheckEvent(const AppleEvent *ev, AppleEvent *reply, long refcon) {
    if (alreadyLoaded) {
        return noErr;
    }
    reportError(reply, @"TotalTerminal not loaded");
    return 1;
}