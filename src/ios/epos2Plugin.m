#import "epos2Plugin.h"
#import <UIKit/UIKit.h>
#import <Cordova/CDVAvailability.h>

static NSDictionary *printerTypeMap;

@interface epos2Plugin()<Epos2DiscoveryDelegate, Epos2PtrReceiveDelegate>
@end

@implementation epos2Plugin

- (void)pluginInitialize
{
    sendDataCallbackId = nil;
    printerTarget = nil;
    printerStatus = nil;
    printerConnected = NO;
    printerSeries = EPOS2_TM_M10;
    lang = EPOS2_MODEL_ANK;
    
    printerTypeMap = @{
        @"TM-M10":    [NSNumber numberWithInt:EPOS2_TM_M10],
        @"TM-M30":    [NSNumber numberWithInt:EPOS2_TM_M30],
        @"TM-P10":    [NSNumber numberWithInt:EPOS2_TM_P20],
        @"TM-P60":    [NSNumber numberWithInt:EPOS2_TM_P60],
        @"TM-P60II":  [NSNumber numberWithInt:EPOS2_TM_P60II],
        @"TM-P80":    [NSNumber numberWithInt:EPOS2_TM_P80],
        @"TM-T20":    [NSNumber numberWithInt:EPOS2_TM_T20],
        @"TM-T60":    [NSNumber numberWithInt:EPOS2_TM_T60],
        @"TM-T70":    [NSNumber numberWithInt:EPOS2_TM_T70],
        @"TM-T81":    [NSNumber numberWithInt:EPOS2_TM_T81],
        @"TM-T82":    [NSNumber numberWithInt:EPOS2_TM_T82],
        @"TM-T83":    [NSNumber numberWithInt:EPOS2_TM_T83],
        @"TM-T88":    [NSNumber numberWithInt:EPOS2_TM_T88],
        @"TM-T88VI":  [NSNumber numberWithInt:EPOS2_TM_T88],
        @"TM-T90":    [NSNumber numberWithInt:EPOS2_TM_T90],
        @"TM-T90KP":  [NSNumber numberWithInt:EPOS2_TM_T90KP],
        @"TM-U220":   [NSNumber numberWithInt:EPOS2_TM_U220],
        @"TM-U330":   [NSNumber numberWithInt:EPOS2_TM_U330],
        @"TM-L90":    [NSNumber numberWithInt:EPOS2_TM_L90],
        @"TM-H6000":  [NSNumber numberWithInt:EPOS2_TM_H6000]
    };
}

- (void)startDiscover:(CDVInvokedUrlCommand *)command
{
    self.discoverCallbackId = command.callbackId;
    
    // stop running discovery first
    int result = EPOS2_SUCCESS;
    
    while (YES) {
        result = [Epos2Discovery stop];
        
        if (result != EPOS2_ERR_PROCESSING) {
            break;
        }
    }
    
    NSLog(@"[epos2] startDiscover: %@", command.callbackId);
    
    Epos2FilterOption *filteroption_ = [[Epos2FilterOption alloc] init];
    [filteroption_ setDeviceType:EPOS2_TYPE_PRINTER];
    [filteroption_ setDeviceModel:EPOS2_MODEL_ALL];
    
    result = [Epos2Discovery start:filteroption_ delegate:self];
    if (EPOS2_SUCCESS != result) {
        NSLog(@"[epos2] Error in startDiscover()");
        CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Error 0x00001: Printer discovery failed"];
        [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
    }
}

- (void) onDiscovery:(Epos2DeviceInfo *)deviceInfo
{
    NSLog(@"[epos2] onDiscovery: %@ (%@)", [deviceInfo getTarget], [deviceInfo getDeviceName]);
    NSDictionary *info = @{
        @"target": [deviceInfo getTarget],
        @"deviceType": [NSNumber numberWithInt:[deviceInfo getDeviceType]],
        @"deviceName": [deviceInfo getDeviceName],
        @"ipAddress" : [deviceInfo getIpAddress],
        @"macAddress": [deviceInfo getMacAddress],
        @"bdAddress": [deviceInfo getBdAddress],
    };
    CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:info];
    [result setKeepCallbackAsBool:YES];
    [self.commandDelegate sendPluginResult:result callbackId:self.discoverCallbackId];
}

- (void)stopDiscover:(CDVInvokedUrlCommand *)command
{
    NSLog(@"[epos2] stopDiscover()");
    int result = EPOS2_SUCCESS;
    
    while (YES) {
        result = [Epos2Discovery stop];
        
        if (result != EPOS2_ERR_PROCESSING) {
            break;
        }
    }
    
    if (EPOS2_SUCCESS != result) {
        NSLog(@"[epos2] Error in stopDiscover()");
        CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Error 0x00002: Stopping discovery failed."];
        [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
    }
}


-(void)connectPrinter:(CDVInvokedUrlCommand *)command
{
    NSString *target = [command.arguments objectAtIndex:0];
    int typeEnum = -1;
    
    // device type is provided
    if ([command.arguments count] > 1) {
        // map device type string to EPOS2_* constant
        typeEnum = [self printerTypeFromString:[command.arguments objectAtIndex:1]];
        NSLog(@"[epos2] set printerSeries to %@ (%d)", [command.arguments objectAtIndex:1], typeEnum);
        if (typeEnum >= 0) {
            printerSeries = typeEnum;
        }
    }
    
    int result = EPOS2_SUCCESS;
    
    // select BT device from accessory list
    if ([target length] == 0) {
        Epos2BluetoothConnection *btConnection = [[Epos2BluetoothConnection alloc] init];
        NSMutableString *BDAddress = [[NSMutableString alloc] init];
        result = [btConnection connectDevice:BDAddress];
        if (result == EPOS2_SUCCESS) {
            target = BDAddress;
        } else {
            CDVPluginResult *cordovaResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Error 0x00010: Bluetooth connection failed"];
            [self.commandDelegate sendPluginResult:cordovaResult callbackId:command.callbackId];
            return;
        }
    }
    
    NSLog(@"[epos2] connectPrinter(%@)", target);
    
    // check for existing connection
    if (printer != nil && printerConnected && ![printerTarget isEqual:target]) {
        CDVPluginResult *cordovaResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Error 0x00011: Printer already connected"];
        [self.commandDelegate sendPluginResult:cordovaResult callbackId:command.callbackId];
        return;
    }
    
    // store the provided target addrss
    printerTarget = target;
    
    if ([self _connectPrinter]) {
        CDVPluginResult *cordovaResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsBool:YES];
        [self.commandDelegate sendPluginResult:cordovaResult callbackId:command.callbackId];
    } else {
        CDVPluginResult *cordovaResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Error 0x00012: Connecting printer failed"];
        [self.commandDelegate sendPluginResult:cordovaResult callbackId:command.callbackId];
    }
}

- (void)disconnectPrinter:(CDVInvokedUrlCommand *)command
{
    int result = EPOS2_SUCCESS;
    CDVPluginResult *cordovaResult = nil;

    NSLog(@"[epos2] disconnectPrinter(%@)", printer);
  
    if (printer == nil) {
        cordovaResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsBool:YES];
        [self.commandDelegate sendPluginResult:cordovaResult callbackId:command.callbackId];
        return;
    }
    
    result = [printer endTransaction];
    if (result != EPOS2_SUCCESS) {
        NSLog(@"[epos2] Error in Epos2Printer.endTransaction(): %d", result);
        cordovaResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Error 0x00020: Ending transaction failed"];
    }
    
    result = [printer disconnect];
    if (result != EPOS2_SUCCESS) {
        NSLog(@"[epos2] Error in Epos2Printer.disconnect(): %d", result);
        cordovaResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Error 0x00021: Disconnecting printer failed"];
    }
    [self finalizeObject];
    
    // return OK result
    if (cordovaResult == nil) {
        cordovaResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsBool:YES];
    }
    
    if (command != nil) {
        [self.commandDelegate sendPluginResult:cordovaResult callbackId:command.callbackId];
    }
}

-(BOOL)_connectPrinter
{
    int result = EPOS2_SUCCESS;
    
    if (printerTarget == nil) {
        return NO;
    }
    
    if (printerConnected) {
        return YES;
    }
    
    NSLog(@"[epos2] _connectPrinter() to %@", printerTarget);
    
    // initialize printer
    if (printer == nil) {
        printer = [[Epos2Printer alloc] initWithPrinterSeries:printerSeries lang:lang];
        [printer setReceiveEventDelegate:self];
    }
    
    result = [printer connect:printerTarget timeout:EPOS2_PARAM_DEFAULT];
    if (result != EPOS2_SUCCESS) {
        NSLog(@"[epos2] Error in Epos2Printer.connect(): %d", result);
        return NO;
    }
    
    result = [printer beginTransaction];
    if (result != EPOS2_SUCCESS) {
        NSLog(@"[epos2] Error in Epos2Printer.beginTransaction(): %d", result);
        [printer disconnect];
        return NO;
    }
    
    printerConnected = YES;
    return YES;
}

- (void)finalizeObject
{
    if (printer == nil) {
        return;
    }
    
    [printer clearCommandBuffer];
    
    [printer setReceiveEventDelegate:nil];
    
    printerConnected = NO;
    printerStatus = nil;
    printer = nil;
}

- (void)onPtrReceive:(Epos2Printer *)printerObj code:(int)code status:(Epos2PrinterStatusInfo *)status printJobId:(NSString *)printJobId
{
    CDVPluginResult *cordovaResult;
    NSLog(@"[epos2] onPtrReceive; code: %d, status: %@, printJobId: %@", code, status, printJobId);
    
    // send callback for sendData command
    if (sendDataCallbackId != nil) {
        if (code == EPOS2_SUCCESS) {
            cordovaResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsBool:YES];
        } else {
            cordovaResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Error 0x00050: Print job failed. Check the device."];
        }
        [self.commandDelegate sendPluginResult:cordovaResult callbackId:sendDataCallbackId];
    }
}

- (void)printText:(CDVInvokedUrlCommand *)command
{
    // (re-)connect printer with stored information
    if (![self _connectPrinter]) {
        CDVPluginResult *cordovaResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Error 0x00013: Printer is not connected"];
        [self.commandDelegate sendPluginResult:cordovaResult callbackId:command.callbackId];
        return;
    }
    
    NSString *printCallbackId = command.callbackId;
    NSArray *printData = [command.arguments objectAtIndex:0];
    int textFont = EPOS2_PARAM_DEFAULT;
    int textSize = EPOS2_PARAM_DEFAULT;
    int textAlign = EPOS2_PARAM_DEFAULT;
    
    // read optional arguments
    if ([command.arguments count] > 1) {
        textFont = ((NSNumber *)[command.arguments objectAtIndex:1]).intValue;
    }
    if ([command.arguments count] > 2) {
        textSize = ((NSNumber *)[command.arguments objectAtIndex:2]).intValue;
    }
    if ([command.arguments count] > 3) {
        textAlign = ((NSNumber *)[command.arguments objectAtIndex:3]).intValue;
    }
    
    [self.commandDelegate runInBackground:^{
        int result = EPOS2_SUCCESS;
        CDVPluginResult *cordovaResult;
        
        result = [printer addTextFont:textFont];
        
        if (result == EPOS2_SUCCESS) {
            result = [printer addTextSize:textSize height:textSize];
        }
        
        if (result == EPOS2_SUCCESS) {
            result = [printer addTextAlign:textAlign];
        }
        
        if (result == EPOS2_SUCCESS) {
            for (NSString *data in printData) {
                if ([data isEqualToString:@"\n"]) {
                    result = [printer addFeedLine:1];
                } else {
                    result = [printer addText:data];
                }
                
                if (result != EPOS2_SUCCESS) {
                    break;
                }
            }
        }
        
        if (result == EPOS2_SUCCESS) {
            cordovaResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsBool:YES];
        } else {
            cordovaResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Error 0x00030: Failed to add text data"];
        }
        
        [self.commandDelegate sendPluginResult:cordovaResult callbackId:printCallbackId];
    }];
}

- (void)printImage:(CDVInvokedUrlCommand *)command
{
    // read command arguments
    NSString *data = [command.arguments objectAtIndex:0];
    int printMode = EPOS2_MODE_MONO;
    int halfTone = EPOS2_HALFTONE_THRESHOLD;
    
    if ([command.arguments count] > 1) {
        printMode = ((NSNumber *)[command.arguments objectAtIndex:1]).intValue;
    }
    if ([command.arguments count] > 2) {
        halfTone = ((NSNumber *)[command.arguments objectAtIndex:2]).intValue;
    }
    
    // (re-)connect printer with stored information
    if (![self _connectPrinter]) {
        CDVPluginResult *cordovaResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Error 0x00013: Printer is not connected"];
        [self.commandDelegate sendPluginResult:cordovaResult callbackId:command.callbackId];
        return;
    }
    
    NSString *printCallbackId = command.callbackId;
    
    // create UIImage from base64 data argument
    //NSData *imageData = [[NSData alloc] initWithBase64EncodedString:data options:0];
    
    // create UIImage from (data) url
    NSURL *url = [NSURL URLWithString:data];
    NSData *imageData = [NSData dataWithContentsOfURL:url];
    UIImage *image = [UIImage imageWithData:imageData];
    
    NSLog(@"[epos2] addImage with data: %dx%d pixels", (int)image.size.width, (int)image.size.height);
    
    [self.commandDelegate runInBackground:^{
        int result = EPOS2_SUCCESS;
        CDVPluginResult *cordovaResult;
        
        result = [printer addImage:image x:0 y:0
                             width:image.size.width
                            height:image.size.height
                             color:EPOS2_COLOR_1
                              mode:printMode
                          halftone:halfTone
                        brightness:EPOS2_PARAM_DEFAULT
                          compress:EPOS2_COMPRESS_AUTO];
        if (result != EPOS2_SUCCESS) {
            NSLog(@"[epos2] Error in Epos2Printer.addImage(): %d", result);
            cordovaResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Error 0x00040: Failed to add image data"];
        } else {
            cordovaResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsBool:YES];
        }
        
        [self.commandDelegate sendPluginResult:cordovaResult callbackId:printCallbackId];
    }];
}

- (void)sendData:(CDVInvokedUrlCommand *)command
{
    sendDataCallbackId = command.callbackId;
    
    // check printer status (cached)
    if (printerStatus == nil) {
        printerStatus = [printer getStatus];
    }

    if (![self isPrintable:printerStatus]) {
        [printer clearCommandBuffer];
        printerStatus = nil;

        CDVPluginResult *cordovaResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Error 0x00050: Printer is not ready. Check device and paper."];
        [self.commandDelegate sendPluginResult:cordovaResult callbackId:command.callbackId];
        return;
    }
    
    [self.commandDelegate runInBackground:^{
        int result = EPOS2_SUCCESS;
        CDVPluginResult *cordovaResult;
        
        // feed paper
        result = [printer addFeedLine:3];
        if (result != EPOS2_SUCCESS) {
            NSLog(@"[epos2] Error in Epos2Printer.addFeedLine(): %d", result);
            return;
        }
        
        // send cut command
        result = [printer addCut:EPOS2_CUT_FEED];
        if (result != EPOS2_SUCCESS) {
            NSLog(@"[epos2] Error in Epos2Printer.addCut(): %d", result);
            return;
        }
        
        result = [printer sendData:EPOS2_PARAM_DEFAULT];
        if (result != EPOS2_SUCCESS) {
            [printer disconnect];
            [self finalizeObject];
            cordovaResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Error 0x00051: Failed to send print job"];
            [self.commandDelegate sendPluginResult:cordovaResult callbackId:sendDataCallbackId];
        } else {
            [printer clearCommandBuffer];
        }
      
        // do not yet trigger callback but wait for onPtrReceive
    }];
}

- (void)getPrinterStatus:(CDVInvokedUrlCommand *)command
{
    // (re-)connect printer with stored information
    if (![self _connectPrinter]) {
        CDVPluginResult *cordovaResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Error 0x00013: Printer is not connected"];
        [self.commandDelegate sendPluginResult:cordovaResult callbackId:command.callbackId];
        return;
    }
    
    // request printer status
    printerStatus = [printer getStatus];
    
    // translate status into a dict for returning
    NSDictionary *info = @{
        @"online": [NSNumber numberWithInt:printerStatus.online],
        @"connection": [NSNumber numberWithInt:printerStatus.connection],
        @"coverOpen": [NSNumber numberWithInt:printerStatus.coverOpen],
        @"paper": [NSNumber numberWithInt:printerStatus.paper],
        @"paperFeed": [NSNumber numberWithInt:printerStatus.paperFeed],
        @"errorStatus": [NSNumber numberWithInt:printerStatus.errorStatus],
        @"isPrintable": [NSNumber numberWithBool:[self isPrintable:printerStatus]]
    };
    
    NSLog(@"[epos2] getPrinterStatus(): %@", info);
    CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:info];
    [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
}

- (void)getSupportedModels:(CDVInvokedUrlCommand *)command
{
    NSArray *types = [printerTypeMap allKeys];
    NSLog(@"[epos2] getSupportedModels(): %@", types);
    CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:types];
    [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
}

- (BOOL)isPrintable:(Epos2PrinterStatusInfo *)status
{
    if (status == nil) {
        return NO;
    }
    
    if (status.connection == EPOS2_FALSE) {
        return NO;
    } else if (status.online == EPOS2_FALSE) {
        return NO;
    } else if (status.coverOpen == EPOS2_TRUE) {
        return NO;
    } else if (status.paper == EPOS2_PAPER_EMPTY) {
        return NO;
    } else if (status.errorStatus != EPOS2_NO_ERR) {
        return NO;
    } else {
        ; // printer is ready
    }
    
    return YES;
}

- (int)printerTypeFromString:(NSString*)type
{
    NSNumber *match = [printerTypeMap objectForKey:type];
    if (match != nil) {
        return [match intValue];
    } else {
        return -1;
    }
}

@end
