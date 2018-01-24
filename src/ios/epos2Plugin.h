#import <Cordova/CDVPlugin.h>
#import "ePOS2.h"

@interface epos2Plugin : CDVPlugin
{
    Epos2Printer *printer;
    Epos2PrinterStatusInfo *printerStatus;
    NSString *sendDataCallbackId;
    NSString *printerTarget;
    BOOL printerConnected;
    int printerSeries;
    int lang;
}

@property (nonatomic, strong) NSString* discoverCallbackId;

// The hooks for our plugin commands
- (void)startDiscover:(CDVInvokedUrlCommand *)command;
- (void)stopDiscover:(CDVInvokedUrlCommand *)command;
- (void)connectPrinter:(CDVInvokedUrlCommand *)command;
- (void)disconnectPrinter:(CDVInvokedUrlCommand *)command;
- (void)printText:(CDVInvokedUrlCommand *)command;
- (void)printImage:(CDVInvokedUrlCommand *)command;
- (void)sendData:(CDVInvokedUrlCommand *)command;

@end
