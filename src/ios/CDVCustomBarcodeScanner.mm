/*
 * PhoneGap is available under *either* the terms of the modified BSD license *or* the
 * MIT License (2008). See http://opensource.org/licenses/alphabetical for full text.
 *
 * Copyright 2011 Matt Kane. All rights reserved.
 * Copyright (c) 2011, IBM Corporation
 */

#import <AVFoundation/AVFoundation.h>
#import <AssetsLibrary/AssetsLibrary.h>

//------------------------------------------------------------------------------
// Import the ZXing definitions
//------------------------------------------------------------------------------
#import "ZXingObjC/ZXingObjC.h"
#import <Cordova/CDVPlugin.h>


//------------------------------------------------------------------------------
// Delegate to handle orientation functions
//------------------------------------------------------------------------------
@protocol CDVBarcodeScannerOrientationDelegate <NSObject>

- (NSUInteger)supportedInterfaceOrientations;
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation;
- (BOOL)shouldAutorotate;

@end

//------------------------------------------------------------------------------
// Adds a shutter button to the UI, and changes the scan from continuous to
// only performing a scan when you click the shutter button.  For testing.
//------------------------------------------------------------------------------
#define USE_SHUTTER 0

//------------------------------------------------------------------------------
@class CDVbcsProcessorCustom;
@class CDVbcsViewControllerCustom;

//------------------------------------------------------------------------------
// plugin class
//------------------------------------------------------------------------------
@interface CDVCustomBarcodeScanner : CDVPlugin {}
- (NSString*)isScanNotPossible;
- (void)scan:(CDVInvokedUrlCommand*)command;
- (void)encode:(CDVInvokedUrlCommand*)command;
- (void)returnImage:(NSString*)filePath format:(NSString*)format callback:(NSString*)callback;
- (void)returnSuccess:(NSString*)scannedText format:(NSString*)format cancelled:(BOOL)cancelled flipped:(BOOL)flipped callback:(NSString*)callback;
- (void)returnError:(NSString*)message callback:(NSString*)callback;
@end

//------------------------------------------------------------------------------
// class that does the grunt work
//------------------------------------------------------------------------------
@interface CDVbcsProcessorCustom : NSObject <AVCaptureVideoDataOutputSampleBufferDelegate> {}
@property (nonatomic, retain) CDVCustomBarcodeScanner*           plugin;
@property (nonatomic, retain) NSString*                   callback;
@property (nonatomic, retain) UIViewController*           parentViewController;
@property (nonatomic, retain) CDVbcsViewControllerCustom*        viewController;
@property (nonatomic, retain) AVCaptureSession*           captureSession;
@property (nonatomic, retain) AVCaptureVideoPreviewLayer* previewLayer;
@property (nonatomic, retain) NSString*                   alternateXib;
@property (nonatomic, retain) NSMutableArray*             results;
@property (nonatomic, retain) NSString*                   formats;
@property (nonatomic)         BOOL                        is1D;
@property (nonatomic)         BOOL                        is2D;
@property (nonatomic)         BOOL                        capturing;
@property (nonatomic)         BOOL                        isFrontCamera;
@property (nonatomic)         BOOL                        isShowFlipCameraButton;
@property (nonatomic)         BOOL                        isShowTorchButton;
@property (nonatomic)         BOOL                        isFlipped;
@property (nonatomic)         BOOL                        isTransitionAnimated;
@property (nonatomic)         BOOL                        isSuccessBeepEnabled;


- (id)initWithPlugin:(CDVCustomBarcodeScanner*)plugin callback:(NSString*)callback parentViewController:(UIViewController*)parentViewController alterateOverlayXib:(NSString *)alternateXib;
- (void)scanBarcode;
- (void)barcodeScanSucceeded:(NSString*)text format:(NSString*)format;
- (void)barcodeScanFailed:(NSString*)message;
- (void)barcodeScanCancelled;
- (void)openDialog;
- (NSString*)setUpCaptureSession;
- (void)captureOutput:(AVCaptureOutput*)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection*)connection;
- (NSString*)barcodeFormatToString:(ZXBarcodeFormat)format;
- (UIImage*)getImageFromSample:(CMSampleBufferRef)sampleBuffer;
- (void)dumpImage:(UIImage*)image;
@end

//------------------------------------------------------------------------------
// Qr encoder processor
//------------------------------------------------------------------------------
@interface CDVqrProcessorCustom: NSObject
@property (nonatomic, retain) CDVCustomBarcodeScanner*          plugin;
@property (nonatomic, retain) NSString*                   callback;
@property (nonatomic, retain) NSString*                   stringToEncode;
@property                     NSInteger                   size;

- (id)initWithPlugin:(CDVCustomBarcodeScanner*)plugin callback:(NSString*)callback stringToEncode:(NSString*)stringToEncode;
- (void)generateImage;
@end

//------------------------------------------------------------------------------
// view controller for the ui
//------------------------------------------------------------------------------
@interface CDVbcsViewControllerCustom : UIViewController <CDVBarcodeScannerOrientationDelegate> {}
@property (nonatomic, retain) CDVbcsProcessorCustom*  processor;
@property (nonatomic, retain) NSString*        alternateXib;
@property (nonatomic)         BOOL             shutterPressed;
@property (nonatomic, retain) IBOutlet UIView* overlayView;
// unsafe_unretained is equivalent to assign - used to prevent retain cycles in the property below
@property (nonatomic, unsafe_unretained) id orientationDelegate;

- (id)initWithProcessor:(CDVbcsProcessorCustom*)processor alternateOverlay:(NSString *)alternateXib;
- (void)startCapturing;
- (UIView*)buildOverlayView;
- (UIImage*)buildReticleImage;
- (void)shutterButtonPressed;
- (IBAction)cancelButtonPressed:(id)sender;

@end

//------------------------------------------------------------------------------
// plugin class
//------------------------------------------------------------------------------
@implementation CDVCustomBarcodeScanner

//--------------------------------------------------------------------------
- (NSString*)isScanNotPossible {
    NSString* result = nil;

    Class aClass = NSClassFromString(@"AVCaptureSession");
    if (aClass == nil) {
        return @"AVFoundation Framework not available";
    }

    return result;
}

-(BOOL)notHasPermission
{
    AVAuthorizationStatus authStatus = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    return (authStatus == AVAuthorizationStatusDenied ||
            authStatus == AVAuthorizationStatusRestricted);
}



//--------------------------------------------------------------------------
- (void)scan:(CDVInvokedUrlCommand*)command {
    CDVbcsProcessorCustom* processor;
    NSString*       callback;
    NSString*       capabilityError;

    callback = command.callbackId;

    NSDictionary* options;
    if (command.arguments.count == 0) {
        options = [NSDictionary dictionary];
    } else {
        options = command.arguments[0];
    }

    BOOL preferFrontCamera = [options[@"preferFrontCamera"] boolValue];
    BOOL showFlipCameraButton = [options[@"showFlipCameraButton"] boolValue];
    BOOL showTorchButton = [options[@"showTorchButton"] boolValue];
    BOOL disableAnimations = [options[@"disableAnimations"] boolValue];
    BOOL disableSuccessBeep = [options[@"disableSuccessBeep"] boolValue];

    // We allow the user to define an alternate xib file for loading the overlay.
    NSString *overlayXib = options[@"overlayXib"];

    capabilityError = [self isScanNotPossible];
    if (capabilityError) {
        [self returnError:capabilityError callback:callback];
        return;
    } else if ([self notHasPermission]) {
        NSString * error = NSLocalizedString(@"Access to the camera has been prohibited; please enable it in the Settings app to continue.",nil);
        [self returnError:error callback:callback];
        return;
    }

    processor = [[[CDVbcsProcessorCustom alloc]
                  initWithPlugin:self
                  callback:callback
                  parentViewController:self.viewController
                  alterateOverlayXib:overlayXib
                  ] autorelease];
    // queue [processor scanBarcode] to run on the event loop

    if (preferFrontCamera) {
        processor.isFrontCamera = true;
    }

    if (showFlipCameraButton) {
    processor.isShowFlipCameraButton = true;
    }

    if (showTorchButton) {
        processor.isShowTorchButton = true;
    }

    processor.isSuccessBeepEnabled = !disableSuccessBeep;

    processor.isTransitionAnimated = !disableAnimations;

    processor.formats = options[@"formats"];

    [processor performSelector:@selector(scanBarcode) withObject:nil afterDelay:0];
}

//--------------------------------------------------------------------------
- (void)encode:(CDVInvokedUrlCommand*)command {
    if([command.arguments count] < 1)
        [self returnError:@"Too few arguments!" callback:command.callbackId];

CDVqrProcessorCustom* processor;
    NSString*       callback;
    callback = command.callbackId;

    processor = [[CDVqrProcessorCustom alloc]
                 initWithPlugin:self
                 callback:callback
                 stringToEncode: command.arguments[0][@"data"]
                 ];

    [processor retain];
    [processor retain];
    [processor retain];
    // queue [processor generateImage] to run on the event loop
    [processor performSelector:@selector(generateImage) withObject:nil afterDelay:0];
}

- (void)returnImage:(NSString*)filePath format:(NSString*)format callback:(NSString*)callback{
    NSMutableDictionary* resultDict = [[[NSMutableDictionary alloc] init] autorelease];
    resultDict[@"format"] = format;
    resultDict[@"file"] = filePath;

    CDVPluginResult* result = [CDVPluginResult
                               resultWithStatus: CDVCommandStatus_OK
                               messageAsDictionary:resultDict
                               ];

    [[self commandDelegate] sendPluginResult:result callbackId:callback];
}

//--------------------------------------------------------------------------
- (void)returnSuccess:(NSString*)scannedText format:(NSString*)format cancelled:(BOOL)cancelled flipped:(BOOL)flipped callback:(NSString*)callback{
    NSNumber* cancelledNumber = @(cancelled ? 1 : 0);

    NSMutableDictionary* resultDict = [[NSMutableDictionary new] autorelease];
    resultDict[@"text"] = scannedText;
    resultDict[@"format"] = format;
    resultDict[@"cancelled"] = cancelledNumber;

    CDVPluginResult* result = [CDVPluginResult
                               resultWithStatus: CDVCommandStatus_OK
                               messageAsDictionary: resultDict
                               ];
    [self.commandDelegate sendPluginResult:result callbackId:callback];
}

//--------------------------------------------------------------------------
- (void)returnError:(NSString*)message callback:(NSString*)callback {
    CDVPluginResult* result = [CDVPluginResult
                               resultWithStatus: CDVCommandStatus_ERROR
                               messageAsString: message
                               ];

    [self.commandDelegate sendPluginResult:result callbackId:callback];
}

@end

//------------------------------------------------------------------------------
// class that does the grunt work
//------------------------------------------------------------------------------
@implementation CDVbcsProcessorCustom

@synthesize plugin               = _plugin;
@synthesize callback             = _callback;
@synthesize parentViewController = _parentViewController;
@synthesize viewController       = _viewController;
@synthesize captureSession       = _captureSession;
@synthesize previewLayer         = _previewLayer;
@synthesize alternateXib         = _alternateXib;
@synthesize is1D                 = _is1D;
@synthesize is2D                 = _is2D;
@synthesize capturing            = _capturing;
@synthesize results              = _results;

SystemSoundID _soundFileObjectCustom;

//--------------------------------------------------------------------------
- (id)initWithPlugin:(CDVCustomBarcodeScanner*)plugin
            callback:(NSString*)callback
parentViewController:(UIViewController*)parentViewController
  alterateOverlayXib:(NSString *)alternateXib
{
    self = [super init];
    if (!self) return self;

    self.plugin               = plugin;
    self.callback             = callback;
    self.parentViewController = parentViewController;
    self.alternateXib         = alternateXib;

    self.is1D      = YES;
    self.is2D      = YES;
    self.capturing = NO;
    self.results = [[NSMutableArray new] autorelease];

    CFURLRef soundFileURLRef  = CFBundleCopyResourceURL(CFBundleGetMainBundle(), CFSTR("CDVCustomBarcodeScanner.bundle/beep"), CFSTR ("caf"), NULL);
    AudioServicesCreateSystemSoundID(soundFileURLRef, &_soundFileObjectCustom);

    return self;
}

//--------------------------------------------------------------------------
- (void)dealloc {
    self.plugin = nil;
    self.callback = nil;
    self.parentViewController = nil;
    self.viewController = nil;
    self.captureSession = nil;
    self.previewLayer = nil;
    self.alternateXib = nil;
    self.results = nil;

    self.capturing = NO;

    AudioServicesRemoveSystemSoundCompletion(_soundFileObjectCustom);
    AudioServicesDisposeSystemSoundID(_soundFileObjectCustom);

    [super dealloc];
}

//--------------------------------------------------------------------------
- (void)scanBarcode {

    //    self.captureSession = nil;
    //    self.previewLayer = nil;
    NSString* errorMessage = [self setUpCaptureSession];
    if (errorMessage) {
        [self barcodeScanFailed:errorMessage];
        return;
    }

    self.viewController = [[[CDVbcsViewControllerCustom alloc] initWithProcessor: self alternateOverlay:self.alternateXib] autorelease];
    // here we set the orientation delegate to the MainViewController of the app (orientation controlled in the Project Settings)
    self.viewController.orientationDelegate = self.plugin.viewController;

    // delayed [self openDialog];
    [self performSelector:@selector(openDialog) withObject:nil afterDelay:1];
}

//--------------------------------------------------------------------------
- (void)openDialog {
    [self.parentViewController
     presentViewController:self.viewController
     animated:self.isTransitionAnimated completion:nil
     ];
}

//--------------------------------------------------------------------------
- (void)barcodeScanDone:(void (^)(void))callbackBlock {
    self.capturing = NO;
    [self.captureSession stopRunning];
    [self.parentViewController dismissViewControllerAnimated:self.isTransitionAnimated completion:callbackBlock];

    // viewcontroller holding onto a reference to us, release them so they
    // will release us
    self.viewController = nil;
}

//--------------------------------------------------------------------------
- (BOOL)checkResult:(NSString *)result {
    [self.results addObject:result];

    NSInteger treshold = 7;

    if (self.results.count > treshold) {
        [self.results removeObjectAtIndex:0];
    }

    if (self.results.count < treshold)
    {
        return NO;
    }

    BOOL allEqual = YES;
    NSString *compareString = self.results[0];

    for (NSString *aResult in self.results)
    {
        if (![compareString isEqualToString:aResult])
        {
            allEqual = NO;
            //NSLog(@"Did not fit: %@",self.results);
            break;
        }
    }

    return allEqual;
}

//--------------------------------------------------------------------------
- (void)barcodeScanSucceeded:(NSString*)text format:(NSString*)format {
    dispatch_sync(dispatch_get_main_queue(), ^{
        [self barcodeScanDone:^{
            [self.plugin returnSuccess:text format:format cancelled:FALSE flipped:FALSE callback:self.callback];
        }];
        if (self.isSuccessBeepEnabled) {
            AudioServicesPlaySystemSound(_soundFileObjectCustom);
        }
    });
}

//--------------------------------------------------------------------------
- (void)barcodeScanFailed:(NSString*)message {
    [self barcodeScanDone:^{
        [self.plugin returnError:message callback:self.callback];
    }];
}

//--------------------------------------------------------------------------
- (void)barcodeScanCancelled {
    [self barcodeScanDone:^{
        [self.plugin returnSuccess:@"" format:@"" cancelled:TRUE flipped:self.isFlipped callback:self.callback];
    }];
    if (self.isFlipped) {
        self.isFlipped = NO;
    }
}

- (void)flipCamera {
    self.isFlipped = YES;
    self.isFrontCamera = !self.isFrontCamera;
    [self barcodeScanDone:^{
        if (self.isFlipped) {
            self.isFlipped = NO;
        }
        [self performSelector:@selector(scanBarcode) withObject:nil afterDelay:0.1];
    }];
}

- (void)toggleTorch {
    AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    [device lockForConfiguration:nil];
    if (device.flashActive) {
        [device setTorchMode:AVCaptureTorchModeOff];
        [device setFlashMode:AVCaptureFlashModeOff];
    } else {
        [device setTorchModeOnWithLevel:AVCaptureMaxAvailableTorchLevel error:nil];
        [device setFlashMode:AVCaptureFlashModeOn];
    }
    [device unlockForConfiguration];
}

//--------------------------------------------------------------------------
- (NSString*)setUpCaptureSession {
    NSError* error = nil;

    AVCaptureSession* captureSession = [[[AVCaptureSession alloc] init] autorelease];
    self.captureSession = captureSession;

    AVCaptureDevice* __block device = nil;
    if (self.isFrontCamera) {

        NSArray* devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
        [devices enumerateObjectsUsingBlock:^(AVCaptureDevice *obj, NSUInteger idx, BOOL *stop) {
            if (obj.position == AVCaptureDevicePositionFront) {
                device = obj;
            }
        }];
    } else {
        device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
        if (!device) return @"unable to obtain video capture device";

    }

    // set focus params if available to improve focusing
    [device lockForConfiguration:&error];
    if (error == nil) {
        if([device isFocusModeSupported:AVCaptureFocusModeContinuousAutoFocus]) {
            [device setFocusMode:AVCaptureFocusModeContinuousAutoFocus];
        }
        if([device isAutoFocusRangeRestrictionSupported]) {
            [device setAutoFocusRangeRestriction:AVCaptureAutoFocusRangeRestrictionNear];
        }
    }
    [device unlockForConfiguration];

    AVCaptureDeviceInput* input = [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
    if (!input) return @"unable to obtain video capture device input";

    AVCaptureVideoDataOutput* output = [[[AVCaptureVideoDataOutput alloc] init] autorelease];
    if (!output) return @"unable to obtain video capture output";

    NSDictionary* videoOutputSettings = [NSDictionary
                                         dictionaryWithObject:[NSNumber numberWithInt:kCVPixelFormatType_32BGRA]
                                         forKey:(id)kCVPixelBufferPixelFormatTypeKey
                                         ];

    output.alwaysDiscardsLateVideoFrames = YES;
    output.videoSettings = videoOutputSettings;

    [output setSampleBufferDelegate:self queue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0)];


    if ([captureSession canSetSessionPreset:AVCaptureSessionPresetHigh]) {
        captureSession.sessionPreset = AVCaptureSessionPresetHigh;
    } else if ([captureSession canSetSessionPreset:AVCaptureSessionPresetMedium]) {
        captureSession.sessionPreset = AVCaptureSessionPresetMedium;
    } else {
        return @"unable to preset high nor medium quality video capture";
    }

    if ([captureSession canAddInput:input]) {
        [captureSession addInput:input];
    }
    else {
        return @"unable to add video capture device input to session";
    }

    if ([captureSession canAddOutput:output]) {
        [captureSession addOutput:output];
    }
    else {
        return @"unable to add video capture output to session";
    }

    // setup capture preview layer
    self.previewLayer = [AVCaptureVideoPreviewLayer layerWithSession:captureSession];
    self.previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;

    // run on next event loop pass [captureSession startRunning]
    [captureSession performSelector:@selector(startRunning) withObject:nil afterDelay:0];

    return nil;
}

//--------------------------------------------------------------------------
// this method gets sent the captured frames
//--------------------------------------------------------------------------
- (void)captureOutput:(AVCaptureOutput*)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection*)connection {

    if (!self.capturing) return;

#if USE_SHUTTER
    if (!self.viewController.shutterPressed) return;
    self.viewController.shutterPressed = NO;

    UIView* flashView = [[UIView alloc] initWithFrame:self.viewController.view.frame];
    [flashView setBackgroundColor:[UIColor whiteColor]];
    [self.viewController.view.window addSubview:flashView];

    [UIView
     animateWithDuration:.4f
     animations:^{
         [flashView setAlpha:0.f];
     }
     completion:^(BOOL finished){
         [flashView removeFromSuperview];
     }
     ];

    //         [self dumpImage: [[self getImageFromSample:sampleBuffer] autorelease]];
#endif

    try {
        CVImageBufferRef videoFrame = CMSampleBufferGetImageBuffer(sampleBuffer);
        CGImageRef videoFrameImage = [ZXCGImageLuminanceSource createImageFromBuffer:videoFrame];

        ZXLuminanceSource *source = [[[ZXCGImageLuminanceSource alloc] initWithCGImage:videoFrameImage] autorelease];

        ZXLuminanceSource *sourceInverted= (ZXCGImageLuminanceSource*)source.invert;
        ZXBinaryBitmap *bitmap = [ZXBinaryBitmap binaryBitmapWithBinarizer:[ZXHybridBinarizer binarizerWithSource:sourceInverted]];

        // clean up
        CGImageRelease(videoFrameImage);

        NSError *error = nil;

        // There are a number of hints we can give to the reader, including
        // possible formats, allowed lengths, and the string encoding.
        ZXDecodeHints *hints = [ZXDecodeHints hints];

        ZXMultiFormatReader *reader = [ZXMultiFormatReader reader];
        ZXResult *result = [reader decode:bitmap
                                    hints:hints
                                    error:&error];
        if (result) {
            // The coded result as a string. The raw data can be accessed with
            // result.rawBytes and result.length.
            NSString *contents = result.text;

            // The barcode format, such as a QR code or UPC-A
            ZXBarcodeFormat format = result.barcodeFormat;

            if ([self checkResult:contents]) {
                [self barcodeScanSucceeded:contents format:[self barcodeFormatToString:format]];
            }
        } else {
            // Use error to determine why we didn't get a result, such as a barcode
            // not being found, an invalid checksum, or a format inconsistency.
        }
    }
    catch (...) {
        NSLog(@"decoding: unknown exception");
        [self barcodeScanFailed:@"unknown exception decoding barcode"];
    }

    //        NSTimeInterval timeElapsed  = [NSDate timeIntervalSinceReferenceDate] - timeStart;
    //        NSLog(@"decoding completed in %dms", (int) (timeElapsed * 1000));

}

- (NSString *)barcodeFormatToString:(ZXBarcodeFormat)format {
    switch (format) {
        case kBarcodeFormatAztec:
            return @"AZTEC";

        case kBarcodeFormatCodabar:
            return @"CODABAR";

        case kBarcodeFormatCode39:
            return @"CODE_39";

        case kBarcodeFormatCode93:
            return @"CODE_93";

        case kBarcodeFormatCode128:
            return @"CODE_128";

        case kBarcodeFormatDataMatrix:
            return @"DATA_MATRIX";

        case kBarcodeFormatEan8:
            return @"EAN_8";

        case kBarcodeFormatEan13:
            return @"EAN_13";

        case kBarcodeFormatITF:
            return @"ITF";

        case kBarcodeFormatPDF417:
            return @"PDF_417";

        case kBarcodeFormatQRCode:
            return @"QR_CODE";

        case kBarcodeFormatRSS14:
            return @"RSS_14";

        case kBarcodeFormatRSSExpanded:
            return @"RSS_EXPANDED";

        case kBarcodeFormatUPCA:
            return @"UPC_A";

        case kBarcodeFormatUPCE:
            return @"UPC_E";

        case kBarcodeFormatUPCEANExtension:
            return @"UPC_EAN_EXTENSION";

        default:
            return @"???";
    }
}


//--------------------------------------------------------------------------
// for debugging
//--------------------------------------------------------------------------
- (UIImage*)getImageFromSample:(CMSampleBufferRef)sampleBuffer {
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    CVPixelBufferLockBaseAddress(imageBuffer, 0);

    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer);
    size_t width       = CVPixelBufferGetWidth(imageBuffer);
    size_t height      = CVPixelBufferGetHeight(imageBuffer);

    uint8_t* baseAddress    = (uint8_t*) CVPixelBufferGetBaseAddress(imageBuffer);
    int      length         = (int)(height * bytesPerRow);
    uint8_t* newBaseAddress = (uint8_t*) malloc(length);
    memcpy(newBaseAddress, baseAddress, length);
    baseAddress = newBaseAddress;

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(
                                                 baseAddress,
                                                 width, height, 8, bytesPerRow,
                                                 colorSpace,
                                                 kCGBitmapByteOrder32Little | kCGImageAlphaNoneSkipFirst
                                                 );

    CGImageRef cgImage = CGBitmapContextCreateImage(context);
    UIImage*   image   = [[UIImage alloc] initWithCGImage:cgImage];

    CVPixelBufferUnlockBaseAddress(imageBuffer,0);
    CGContextRelease(context);
    CGColorSpaceRelease(colorSpace);
    CGImageRelease(cgImage);

    free(baseAddress);

    return image;
}

//--------------------------------------------------------------------------
// for debugging
//--------------------------------------------------------------------------
- (void)dumpImage:(UIImage*)image {
    NSLog(@"writing image to library: %dx%d", (int)image.size.width, (int)image.size.height);
    ALAssetsLibrary* assetsLibrary = [[[ALAssetsLibrary alloc] init] autorelease];
    [assetsLibrary
     writeImageToSavedPhotosAlbum:image.CGImage
     orientation:ALAssetOrientationUp
     completionBlock:^(NSURL* assetURL, NSError* error){
         if (error) NSLog(@"   error writing image to library");
         else       NSLog(@"   wrote image to library %@", assetURL);
     }
     ];
}

@end


//------------------------------------------------------------------------------
// qr encoder processor
//------------------------------------------------------------------------------
@implementation CDVqrProcessorCustom
@synthesize plugin               = _plugin;
@synthesize callback             = _callback;
@synthesize stringToEncode       = _stringToEncode;
@synthesize size                 = _size;

- (id)initWithPlugin:(CDVCustomBarcodeScanner*)plugin callback:(NSString*)callback stringToEncode:(NSString*)stringToEncode{
    self = [super init];
    if (!self) return self;

    self.plugin          = plugin;
    self.callback        = callback;
    self.stringToEncode  = stringToEncode;
    self.size            = 300;

    return self;
}

//--------------------------------------------------------------------------
- (void)dealloc {
    self.plugin = nil;
    self.callback = nil;
    self.stringToEncode = nil;

    [super dealloc];
}
//--------------------------------------------------------------------------
- (void)generateImage{
    /* setup qr filter */
    CIFilter *filter = [CIFilter filterWithName:@"CIQRCodeGenerator"];
    [filter setDefaults];

    /* set filter's input message
     * the encoding string has to be convert to a UTF-8 encoded NSData object */
    [filter setValue:[self.stringToEncode dataUsingEncoding:NSUTF8StringEncoding]
              forKey:@"inputMessage"];

    /* on ios >= 7.0  set low image error correction level */
    if (floor(NSFoundationVersionNumber) >= NSFoundationVersionNumber_iOS_7_0)
        [filter setValue:@"L" forKey:@"inputCorrectionLevel"];

    /* prepare cgImage */
    CIImage *outputImage = [filter outputImage];
    CIContext *context = [CIContext contextWithOptions:nil];
    CGImageRef cgImage = [context createCGImage:outputImage
                                       fromRect:[outputImage extent]];

    /* returned qr code image */
    UIImage *qrImage = [UIImage imageWithCGImage:cgImage
                                           scale:1.
                                     orientation:UIImageOrientationUp];
    /* resize generated image */
    CGFloat width = _size;
    CGFloat height = _size;

    UIGraphicsBeginImageContext(CGSizeMake(width, height));

    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextSetInterpolationQuality(ctx, kCGInterpolationNone);
    [qrImage drawInRect:CGRectMake(0, 0, width, height)];
    qrImage = UIGraphicsGetImageFromCurrentImageContext();

    /* clean up */
    UIGraphicsEndImageContext();
    CGImageRelease(cgImage);

    /* save image to file */
    NSString* fileName = [[[NSProcessInfo processInfo] globallyUniqueString] stringByAppendingString:@".jpg"];
    NSString* filePath = [NSTemporaryDirectory() stringByAppendingPathComponent:fileName];
    [UIImageJPEGRepresentation(qrImage, 1.0) writeToFile:filePath atomically:YES];

    /* return file path back to cordova */
    [self.plugin returnImage:filePath format:@"QR_CODE" callback: self.callback];
}
@end

//------------------------------------------------------------------------------
// view controller for the ui
//------------------------------------------------------------------------------
@implementation CDVbcsViewControllerCustom
@synthesize processor      = _processor;
@synthesize shutterPressed = _shutterPressed;
@synthesize alternateXib   = _alternateXib;
@synthesize overlayView    = _overlayView;

//--------------------------------------------------------------------------
- (id)initWithProcessor:(CDVbcsProcessorCustom*)processor alternateOverlay:(NSString *)alternateXib {
    self = [super init];
    if (!self) return self;

    self.processor = processor;
    self.shutterPressed = NO;
    self.alternateXib = alternateXib;
    self.overlayView = nil;
    return self;
}

//--------------------------------------------------------------------------
- (void)dealloc {
    self.view = nil;
    self.processor = nil;
    self.shutterPressed = NO;
    self.alternateXib = nil;
    self.overlayView = nil;
    [super dealloc];
}

//--------------------------------------------------------------------------
- (void)loadView {
    self.view = [[UIView alloc] initWithFrame: self.processor.parentViewController.view.frame];

    // setup capture preview layer
    AVCaptureVideoPreviewLayer* previewLayer = self.processor.previewLayer;
    previewLayer.frame = self.view.bounds;
    previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;

    if ([previewLayer.connection isVideoOrientationSupported]) {
        [previewLayer.connection setVideoOrientation:AVCaptureVideoOrientationPortrait];
    }

    [self.view.layer insertSublayer:previewLayer below:[[self.view.layer sublayers] objectAtIndex:0]];

    [self.view addSubview:[self buildOverlayView]];
}

//--------------------------------------------------------------------------
- (void)viewWillAppear:(BOOL)animated {

    // set video orientation to what the camera sees
    self.processor.previewLayer.connection.videoOrientation = (AVCaptureVideoOrientation) [[UIApplication sharedApplication] statusBarOrientation];

    // this fixes the bug when the statusbar is landscape, and the preview layer
    // starts up in portrait (not filling the whole view)
    self.processor.previewLayer.frame = self.view.bounds;
}

//--------------------------------------------------------------------------
- (void)viewDidAppear:(BOOL)animated {
    [self startCapturing];

    [super viewDidAppear:animated];
}

//--------------------------------------------------------------------------
- (void)startCapturing {
    self.processor.capturing = YES;
}

//--------------------------------------------------------------------------
- (void)shutterButtonPressed {
    self.shutterPressed = YES;
}

//--------------------------------------------------------------------------
- (IBAction)cancelButtonPressed:(id)sender {
    [self.processor performSelector:@selector(barcodeScanCancelled) withObject:nil afterDelay:0];
}

- (void)flipCameraButtonPressed:(id)sender
{
    [self.processor performSelector:@selector(flipCamera) withObject:nil afterDelay:0];
}

- (void)torchButtonPressed:(id)sender
{
    [self.processor performSelector:@selector(toggleTorch) withObject:nil afterDelay:0];
}

//--------------------------------------------------------------------------
- (UIView *)buildOverlayViewFromXib
{
    [[NSBundle mainBundle] loadNibNamed:self.alternateXib owner:self options:NULL];

    if ( self.overlayView == nil )
    {
        NSLog(@"%@", @"An error occurred loading the overlay xib.  It appears that the overlayView outlet is not set.");
        return nil;
    }

    return self.overlayView;
}

//--------------------------------------------------------------------------
- (UIView*)buildOverlayView {

    if ( nil != self.alternateXib )
    {
        return [self buildOverlayViewFromXib];
    }
    CGRect bounds = self.view.bounds;
    bounds = CGRectMake(0, 0, bounds.size.width, bounds.size.height);

    UIView* overlayView = [[UIView alloc] initWithFrame:bounds];
    overlayView.autoresizesSubviews = YES;
    overlayView.autoresizingMask    = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    overlayView.opaque              = NO;

    UIToolbar* toolbar = [[UIToolbar alloc] init];
    toolbar.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;

    id cancelButton = [[[UIBarButtonItem alloc]
                        initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                        target:(id)self
                        action:@selector(cancelButtonPressed:)
                        ] autorelease];


    id flexSpace = [[[UIBarButtonItem alloc]
                     initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace
                     target:nil
                     action:nil
                     ] autorelease];

    id flipCamera = [[[UIBarButtonItem alloc]
                      initWithBarButtonSystemItem:UIBarButtonSystemItemCamera
                      target:(id)self
                      action:@selector(flipCameraButtonPressed:)
                      ] autorelease];

    NSMutableArray *items;

#if USE_SHUTTER
    id shutterButton = [[[UIBarButtonItem alloc]
                         initWithBarButtonSystemItem:UIBarButtonSystemItemCamera
                         target:(id)self
                         action:@selector(shutterButtonPressed)
                         ] autorelease];

    if (_processor.isShowFlipCameraButton) {
        items = [NSMutableArray arrayWithObjects:flexSpace, cancelButton, flexSpace, flipCamera, shutterButton, nil];
    } else {
        items = [NSMutableArray arrayWithObjects:flexSpace, cancelButton, flexSpace, shutterButton, nil];
    }
#else
    if (_processor.isShowFlipCameraButton) {
        items = [@[flexSpace, cancelButton, flexSpace, flipCamera] mutableCopy];
    } else {
        items = [@[flexSpace, cancelButton, flexSpace] mutableCopy];
    }
#endif

    if (_processor.isShowTorchButton && !_processor.isFrontCamera) {
        AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
        if ([device hasTorch] && [device hasFlash]) {
            NSURL *bundleURL = [[NSBundle mainBundle] URLForResource:@"CDVCustomBarcodeScanner" withExtension:@"bundle"];
            NSBundle *bundle = [NSBundle bundleWithURL:bundleURL];
            NSString *imagePath = [bundle pathForResource:@"torch" ofType:@"png"];
            UIImage *image = [UIImage imageWithContentsOfFile:imagePath];

            id torchButton = [[[UIBarButtonItem alloc]
                               initWithImage:image
                               style:UIBarButtonItemStylePlain
                               target:(id)self
                               action:@selector(torchButtonPressed:)
                               ] autorelease];

            [items insertObject:torchButton atIndex:0];
        }
    }

    toolbar.items = items;

    bounds = overlayView.bounds;

    [toolbar sizeToFit];
    CGFloat toolbarHeight  = [toolbar frame].size.height;
    CGFloat rootViewHeight = CGRectGetHeight(bounds);
    CGFloat rootViewWidth  = CGRectGetWidth(bounds);
    CGRect  rectArea       = CGRectMake(0, rootViewHeight - toolbarHeight, rootViewWidth, toolbarHeight);
    [toolbar setFrame:rectArea];

    [overlayView addSubview: toolbar];

    UIImage* reticleImage = [self buildReticleImage];
    UIView* reticleView = [[[UIImageView alloc] initWithImage:reticleImage] autorelease];
    CGFloat minAxis = MIN(rootViewHeight, rootViewWidth);

    rectArea = CGRectMake(
                          (CGFloat) (0.5 * (rootViewWidth  - minAxis)),
                          (CGFloat) (0.5 * (rootViewHeight - minAxis)),
                          minAxis,
                          minAxis
                          );

    [reticleView setFrame:rectArea];

    reticleView.opaque           = NO;
    reticleView.contentMode      = UIViewContentModeScaleAspectFit;
    reticleView.autoresizingMask = (UIViewAutoresizing) (0
                                                         | UIViewAutoresizingFlexibleLeftMargin
                                                         | UIViewAutoresizingFlexibleRightMargin
                                                         | UIViewAutoresizingFlexibleTopMargin
                                                         | UIViewAutoresizingFlexibleBottomMargin)
    ;

    [overlayView addSubview: reticleView];

    return overlayView;
}

//--------------------------------------------------------------------------

#define RETICLE_SIZE    500.0f
#define RETICLE_WIDTH    10.0f
#define RETICLE_OFFSET   60.0f
#define RETICLE_ALPHA     0.4f

//-------------------------------------------------------------------------
// builds the green box and red line
//-------------------------------------------------------------------------
- (UIImage*)buildReticleImage {
    UIImage* result;
    UIGraphicsBeginImageContext(CGSizeMake(RETICLE_SIZE, RETICLE_SIZE));
    CGContextRef context = UIGraphicsGetCurrentContext();

    if (self.processor.is1D) {
        UIColor* color = [UIColor colorWithRed:1.0 green:0.0 blue:0.0 alpha:RETICLE_ALPHA];
        CGContextSetStrokeColorWithColor(context, color.CGColor);
        CGContextSetLineWidth(context, RETICLE_WIDTH);
        CGContextBeginPath(context);
        CGFloat lineOffset = (CGFloat) (RETICLE_OFFSET+(0.5*RETICLE_WIDTH));
        CGContextMoveToPoint(context, lineOffset, RETICLE_SIZE/2);
        CGContextAddLineToPoint(context, RETICLE_SIZE-lineOffset, (CGFloat) (0.5*RETICLE_SIZE));
        CGContextStrokePath(context);
    }

    if (self.processor.is2D) {
        UIColor* color = [UIColor colorWithRed:0.0 green:1.0 blue:0.0 alpha:RETICLE_ALPHA];
        CGContextSetStrokeColorWithColor(context, color.CGColor);
        CGContextSetLineWidth(context, RETICLE_WIDTH);
        CGContextStrokeRect(context,
                            CGRectMake(
                                       RETICLE_OFFSET,
                                       RETICLE_OFFSET,
                                       RETICLE_SIZE-2*RETICLE_OFFSET,
                                       RETICLE_SIZE-2*RETICLE_OFFSET
                                       )
                            );
    }

    result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
}

#pragma mark CDVBarcodeScannerOrientationDelegate

- (BOOL)shouldAutorotate
{
    return YES;
}

- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation
{
    return [[UIApplication sharedApplication] statusBarOrientation];
}

- (NSUInteger)supportedInterfaceOrientations
{
    return UIInterfaceOrientationMaskAll;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    if ((self.orientationDelegate != nil) && [self.orientationDelegate respondsToSelector:@selector(shouldAutorotateToInterfaceOrientation:)]) {
        return [self.orientationDelegate shouldAutorotateToInterfaceOrientation:interfaceOrientation];
    }

    return YES;
}

- (void) willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)orientation duration:(NSTimeInterval)duration
{
    [UIView setAnimationsEnabled:NO];
    AVCaptureVideoPreviewLayer* previewLayer = self.processor.previewLayer;
    previewLayer.frame = self.view.bounds;

    if (orientation == UIInterfaceOrientationLandscapeLeft) {
        [previewLayer setOrientation:AVCaptureVideoOrientationLandscapeLeft];
    } else if (orientation == UIInterfaceOrientationLandscapeRight) {
        [previewLayer setOrientation:AVCaptureVideoOrientationLandscapeRight];
    } else if (orientation == UIInterfaceOrientationPortrait) {
        [previewLayer setOrientation:AVCaptureVideoOrientationPortrait];
    } else if (orientation == UIInterfaceOrientationPortraitUpsideDown) {
        [previewLayer setOrientation:AVCaptureVideoOrientationPortraitUpsideDown];
    }

    previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    [UIView setAnimationsEnabled:YES];
}

@end

