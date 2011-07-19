#import <Cocoa/Cocoa.h>

#import "TFStandardVersionComparator.h"
#import "ini.h"

#define TOTALTERMINAL_STANDARD_INSTALL_LOCATION "/Applications/TotalTerminal.app"
#define TOTALTERMINAL_INI_FILE "~/.totalterminal"
#define TERMINAL_MIN_TESTED_VERSION @"0"
#define TERMINAL_MAX_TESTED_VERSION @"294"

// SIMBL-compatible interface
@interface TotalTerminalPlugin: NSObject { 
}
- (void) install;
@end

static bool alreadyLoaded = false;

typedef struct {
    NSString* location;
} configuration;

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

static int ini_handler(void* user, const char* section, const char* name, const char* value) {
    configuration* config = (configuration*)user;
    
    if ([[NSString stringWithUTF8String:name] isEqualToString:@"location"]) {
        config->location = [[NSString alloc] initWithUTF8String:value];
    }
    return 0;
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
            reportError(reply, [NSString stringWithFormat:@"Unable to locate main Finder bundle!"]);
            return 4;
        }
        
        NSString* terminalVersion = [terminalBundle objectForInfoDictionaryKey:@"CFBundleVersion"];
        if (!terminalVersion) {
            reportError(reply, [NSString stringWithFormat:@"Unable to determine Finder version!"]);
            return 5;
        }
        
        // future compatibility check
        NSString* supressKey = @"TotalTerminalSuppressFinderVersionCheck";
        NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
        if (![defaults boolForKey:supressKey]) {
            TFStandardVersionComparator* comparator = [TFStandardVersionComparator defaultComparator];
            if (([comparator compareVersion:terminalVersion toVersion:TERMINAL_MAX_TESTED_VERSION]==NSOrderedDescending) || 
                ([comparator compareVersion:terminalVersion toVersion:TERMINAL_MIN_TESTED_VERSION]==NSOrderedAscending)) {

                NSAlert* alert = [NSAlert new];
                [alert setMessageText: [NSString stringWithFormat:@"You have Finder version %@", terminalVersion]];
                [alert setInformativeText: [NSString stringWithFormat:@"But TotalTerminal was properly tested only with Finder versions in range %@ - %@\n\nYou have probably updated your system and Finder version got bumped by Apple developers.\n\nYou may expect a new TotalTerminal release soon.", TERMINAL_MIN_TESTED_VERSION, TERMINAL_MAX_TESTED_VERSION]];
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
        
        // read install location from ini file if present, otherwise use standard install location
        configuration config;
        NSString* totalFinderLocation = @TOTALTERMINAL_STANDARD_INSTALL_LOCATION;
        NSString* iniPath = [@TOTALTERMINAL_INI_FILE stringByExpandingTildeInPath];
        if (ini_parse([iniPath cStringUsingEncoding:NSASCIIStringEncoding], ini_handler, &config) >= 0) {
            totalFinderLocation = [config.location stringByStandardizingPath];
            [config.location release];
        }
        
        NSBundle* pluginBundle = [NSBundle bundleWithPath:[totalFinderLocation stringByAppendingPathComponent:@"Contents/Resources/TotalTerminal.bundle"]];
        if (!pluginBundle) {
            reportError(reply, [NSString stringWithFormat:@"Unable to create bundle from path: %@", totalFinderLocation]);
            return 2;
        }
        
        NSError* error;
        if (![pluginBundle loadAndReturnError:&error]) {
            reportError(reply, [NSString stringWithFormat:@"Unable to load bundle from path: %@ error: %@", totalFinderLocation, [error localizedDescription]]);
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