//
//  MIT License
//
//  Copyright (c) 2014 Bob McCune http://bobmccune.com/
//  Copyright (c) 2014 TapHarmonic, LLC http://tapharmonic.com/
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

#import "THCameraController.h"
#import <AVFoundation/AVFoundation.h>
#import <AssetsLibrary/AssetsLibrary.h>
#import "NSFileManager+THAdditions.h"

NSString *const THThumbnailCreatedNotification = @"THThumbnailCreated";

@interface THCameraController () <AVCaptureFileOutputRecordingDelegate>

@property (strong, nonatomic) dispatch_queue_t videoQueue;
@property (strong, nonatomic) AVCaptureSession *captureSession;
@property (weak, nonatomic) AVCaptureDeviceInput *activeVideoInput;
@property (strong, nonatomic) AVCaptureStillImageOutput *imageOutput;
@property (strong, nonatomic) AVCaptureMovieFileOutput *movieOutput;
@property (strong, nonatomic) NSURL *outputURL;

@end

@implementation THCameraController

- (BOOL)setupSession:(NSError **)error {

    // Listing 6.4
    self.captureSession = [[AVCaptureSession alloc] init];  // 1
    self.captureSession.sessionPreset = AVCaptureSessionPresetHigh;
    
    // Set up default camera device // 2
    AVCaptureDevice *videoDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo]; // 2
    AVCaptureDeviceInput *videoInput = [AVCaptureDeviceInput deviceInputWithDevice:videoDevice error:error]; // 3
    
    if (videoInput) {
        if ([self.captureSession canAddInput:videoInput]) {   // 4
            [self.captureSession addInput:videoInput];
            self.activeVideoInput = videoInput;
        }
    } else {
        return NO;
    }
    
    // Setup default microphone
    AVCaptureDevice *audioDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];  // 5
    AVCaptureDeviceInput *audioInput = [AVCaptureDeviceInput deviceInputWithDevice:audioDevice error:error]; // 6
    if( audioInput ) {
        if ( [self.captureSession canAddInput:audioInput]) {  // 7
            [self.captureSession addInput:audioInput];
        }
    } else {
        return NO;
    }
    
    // Set up the still image output
    self.imageOutput = [[AVCaptureStillImageOutput alloc] init];   // 8
    self.imageOutput.outputSettings = @{AVVideoCodecKey : AVVideoCodecJPEG};
    
    if([self.captureSession canAddOutput:self.imageOutput]) {
        [self.captureSession addOutput:self.imageOutput];
    }
    
    // Set up movie file output
    self.movieOutput = [[AVCaptureMovieFileOutput alloc] init];   // 9
    
    if ( [self.captureSession canAddOutput:self.movieOutput]) {
        [self.captureSession addOutput:self.movieOutput];
    }
    
    self.videoQueue = dispatch_queue_create("com.tapharmonic.VideoQueue", NULL);
    
    return YES;
}

- (void)startSession {

    // Listing 6.5
    if (![self.captureSession isRunning]) {
        dispatch_async(self.videoQueue, ^{
            [self.captureSession startRunning];
        });
    }
}

- (void)stopSession {

    // Listing 6.5
    if ([self.captureSession isRunning]) {
        dispatch_async(self.videoQueue, ^{
            [self.captureSession stopRunning];
        });
    }

}

#pragma mark - Device Configuration

- (AVCaptureDevice *)cameraWithPosition:(AVCaptureDevicePosition)position {   // 1
    NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    
    for(AVCaptureDevice *device in devices) {
        if (device.position == position) {
            return device;
        }
    }

    // Listing 6.6
    
    return nil;
}

- (AVCaptureDevice *)activeCamera { //2
    return self.activeVideoInput.device;
    
//    return nil;
}

- (AVCaptureDevice *)inactiveCamera { // 3

    // Listing 6.6
    AVCaptureDevice *device = nil;
    if(self.cameraCount > 1) {
        if ([self activeCamera].position == AVCaptureDevicePositionBack) {
            device = [self cameraWithPosition:AVCaptureDevicePositionFront];
        } else {
            device = [self cameraWithPosition:AVCaptureDevicePositionBack];
        }
    }
    return device;
//    return nil;
}

- (BOOL)canSwitchCameras { // 4

    // Listing 6.6
    return self.cameraCount > 1;
//    return NO;
}

- (NSUInteger)cameraCount { //5

    // Listing 6.6
    
    return [[AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo] count];
//    return 0;
}

- (BOOL)switchCameras {

    // Listing 6.7

    if (![self canSwitchCameras]) {  //1
        return NO;
    }
    
    NSError *error;
    AVCaptureDevice *videoDevice = [self inactiveCamera];  //2
    AVCaptureDeviceInput *videoInput = [AVCaptureDeviceInput deviceInputWithDevice:videoDevice error:&error];
    
    if(videoInput){
        [self.captureSession beginConfiguration];  //3
        [self.captureSession removeInput:self.activeVideoInput];  //4
        
        if ([self.captureSession canAddInput:videoInput]) {  // 5
            [self.captureSession addInput:videoInput];
            self.activeVideoInput = videoInput;
        } else {
            [self.captureSession addInput:self.activeVideoInput];
        }
        
        [self.captureSession commitConfiguration];  // 6
    } else {
        [self.delegate deviceConfigurationFailedWithError:error]; // 7
        return NO;
    }
    
    return YES;
}

#pragma mark - Focus Methods

- (BOOL)cameraSupportsTapToFocus {
    // Listing 6.8
    // 1
    return [[self activeCamera] isFocusPointOfInterestSupported];
    
//    return NO;
}

- (void)focusAtPoint:(CGPoint)point {
    // Listing 6.8
    // 2
    
    AVCaptureDevice *device = [self activeCamera];
    
    // 3
    if (device.isFocusPointOfInterestSupported && [device isFocusModeSupported:AVCaptureFocusModeAutoFocus]) {
        NSError *error;
        
        // 4
        if([device lockForConfiguration:&error]) {
            device.focusPointOfInterest = point;
            device.focusMode = AVCaptureFocusModeAutoFocus;
            [device unlockForConfiguration];
        } else {
            [self.delegate deviceConfigurationFailedWithError:error];
        }
    }
    
}

#pragma mark - Exposure Methods

- (BOOL)cameraSupportsTapToExpose {
 
    // Listing 6.9
    
    // 1
    return [[self activeCamera] isExposurePointOfInterestSupported];
//    return NO;
}

// Define KVO centext pointer for observing `adjustingExposure` device property.
static const NSString *THCameraAdjustingExposureContext;

- (void)exposeAtPoint:(CGPoint)point {

    // Listing 6.9
    
    AVCaptureDevice *device = [self activeCamera];
    AVCaptureExposureMode exposureMode = AVCaptureExposureModeContinuousAutoExposure;
    
    // 2
    if ( device. isExposurePointOfInterestSupported && [device isExposureModeSupported:exposureMode]) {
        NSError *error;
        if([device lockForConfiguration:&error]) {
            // 3
            device.exposurePointOfInterest = point;
            device.exposureMode = exposureMode;
            
            if([device isExposureModeSupported:AVCaptureExposureModeLocked]) {
                //4
                [device addObserver:self forKeyPath:@"adjustingExpousre" options:NSKeyValueObservingOptionNew context:&THCameraAdjustingExposureContext];
            }
            [device unlockForConfiguration];
        } else {
            [self.delegate deviceConfigurationFailedWithError:error];
        }
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context {

    // Listing 6.9
    //5
    if(context == &THCameraAdjustingExposureContext) {
        AVCaptureDevice *device = (AVCaptureDevice *) object;
        
        //6
        if(!device.isAdjustingExposure && [device isExposureModeSupported:AVCaptureExposureModeLocked]) {
        
            //7
            [object removeObserver:self forKeyPath:@"adjustingExpousre" context:&THCameraAdjustingExposureContext];
            
            //8
            dispatch_async(dispatch_get_main_queue(), ^{
                NSError *error;
                if([device lockForConfiguration:&error]) {
                    device.exposureMode = AVCaptureExposureModeLocked;
                    [device unlockForConfiguration];
                } else {
                    [self.delegate deviceConfigurationFailedWithError:error];
                }
            });
        }
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

- (void)resetFocusAndExposureModes {

    // Listing 6.10
    
    AVCaptureDevice *device = [self activeCamera];
    AVCaptureFocusMode focusMode = AVCaptureFocusModeContinuousAutoFocus;
    
    // 1
    BOOL canResetFoucus = [device isFocusPointOfInterestSupported] && [device isFocusModeSupported:focusMode];
    
    AVCaptureExposureMode exposureMode = AVCaptureExposureModeContinuousAutoExposure;
    
    // 2
    BOOL canResetExposure = [device isExposurePointOfInterestSupported] && [device isExposureModeSupported:exposureMode];
    
    // 3
    CGPoint centerPoint = CGPointMake(0.5f, 0.5f);
    NSError *error;
    
    if([device lockForConfiguration:&error]) {
        // 4
        if(canResetFoucus) {
            device.focusMode = focusMode;
            device.focusPointOfInterest = centerPoint;
        }
        
        // 5
        if(canResetExposure) {
            device.exposureMode = exposureMode;
            device.exposurePointOfInterest = centerPoint;
        }
        
        [device unlockForConfiguration];
    } else {
        [self.delegate deviceConfigurationFailedWithError:error];
    }
}



#pragma mark - Flash and Torch Modes

- (BOOL)cameraHasFlash {
    // Listing 6.11
    return [[self activeCamera] hasFlash];
    
//    return NO;
}

- (AVCaptureFlashMode)flashMode {

    // Listing 6.11
    
    return [[self activeCamera] flashMode];
//    return 0;
}

- (void)setFlashMode:(AVCaptureFlashMode)flashMode {
    // Listing 6.11
    AVCaptureDevice *device = [self activeCamera];
    
    if([device isFlashModeSupported:flashMode]) {
        NSError *error;
        if([device lockForConfiguration:&error]){
            device.flashMode = flashMode;
            [device unlockForConfiguration];
        } else {
            [self.delegate deviceConfigurationFailedWithError:error];
        }
    }
}

- (BOOL)cameraHasTorch {
    // Listing 6.11
    
    return [[self activeCamera] hasTorch];
    
//    return NO;
}

- (AVCaptureTorchMode)torchMode {
    // Listing 6.11
    
    return [[self activeCamera] torchMode];
    
//    return 0;
}

- (void)setTorchMode:(AVCaptureTorchMode)torchMode {
    // Listing 6.11
    
    AVCaptureDevice *device = [self activeCamera];
    if([device isTorchModeSupported:torchMode]) {
        NSError *error;
        if([device lockForConfiguration:&error]) {
            device.torchMode = torchMode;
            [device unlockForConfiguration];
        } else {
            [self.delegate deviceConfigurationFailedWithError:error];
        }
    }
}


#pragma mark - Image Capture Methods

- (void)captureStillImage {
    // Listing 6.12
    
    // 1
    AVCaptureConnection *connection = [self.imageOutput connectionWithMediaType:AVMediaTypeVideo];
    
    // 2
    if(connection.isVideoOrientationSupported) {
        connection.videoOrientation = [self currentVideoOrientation];
    }
    
    id handler = ^(CMSampleBufferRef sampleBuufer, NSError *error) {
        if(sampleBuufer != NULL) {
            
            // 4
            NSData *imageData = [AVCaptureStillImageOutput jpegStillImageNSDataRepresentation:sampleBuufer];
            
            // 5
            UIImage *image = [[UIImage alloc] initWithData:imageData];
            
            //6.13 - 1
            [self writeImageToAssetsLibrary:image];
            
        } else{
            NSLog(@"NULL sampleBuffer %@", [error localizedDescription]);
        }
    };
    
    //6  capture still image
    [self.imageOutput captureStillImageAsynchronouslyFromConnection:connection completionHandler:handler];

}

- (AVCaptureVideoOrientation)currentVideoOrientation {
    AVCaptureVideoOrientation orientation;
    // Listing 6.12
    // 3
    switch ([UIDevice currentDevice].orientation) {
        case UIDeviceOrientationPortrait:
            orientation = AVCaptureVideoOrientationPortrait;
            break;
        case UIDeviceOrientationLandscapeRight :
            orientation = AVCaptureVideoOrientationLandscapeLeft;
            break;
        case UIDeviceOrientationPortraitUpsideDown:
            orientation = AVCaptureVideoOrientationPortraitUpsideDown;
            break;
        default:
            orientation = AVCaptureVideoOrientationLandscapeRight;
            break;
    }
    
    return orientation;
//    return 0;
}


- (void)writeImageToAssetsLibrary:(UIImage *)image {
    // Listing 6.13
    
    // 2
    ALAssetsLibrary *library = [[ALAssetsLibrary alloc] init];
    
    // 3 & 4
    [library writeImageToSavedPhotosAlbum:image.CGImage orientation:(NSInteger)image.imageOrientation completionBlock:^(NSURL *assetURL, NSError *error) {         
        if(!error) {
            [self postThumbnailNotifification:image]; // 5
        } else {
            id message = [error localizedDescription];
            NSLog(@"Error : %@", message);
        }
    }];
    
}

- (void)postThumbnailNotifification:(UIImage *)image {
    // Listing 6.13
    
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc postNotificationName:THThumbnailCreatedNotification object:image];
    
}

#pragma mark - Video Capture Methods

- (BOOL)isRecording {
    // Listing 6.14
    // 1
    return self.movieOutput.isRecording;
    
//    return NO;
}

- (void)startRecording {
    // Listing 6.14
    
    if(![self isRecording]) {
        // 2
        AVCaptureConnection *videoConnection = [self.movieOutput connectionWithMediaType:AVMediaTypeVideo];
        
        // 3
        if([videoConnection isVideoOrientationSupported]) {
            videoConnection.videoOrientation = self.currentVideoOrientation;
        }
        
        // 4
        if([videoConnection isVideoStabilizationSupported]) {
            videoConnection.preferredVideoStabilizationMode = YES;
//            videoConnection.enablesVideoStabilizationWhenAvailable = YES;  // deprecated
        }
        
        AVCaptureDevice *device = [self activeCamera];
        
        // 5
        if(device.isSmoothAutoFocusEnabled) {
            NSError *error;
            if ([device lockForConfiguration:&error]) {
                device.smoothAutoFocusEnabled = YES;
                [device unlockForConfiguration];
            } else {
                [self.delegate deviceConfigurationFailedWithError:error];
            }
        }
        // 6
        self.outputURL = [self uniqueURL];
        
        // 8
        [self.movieOutput startRecordingToOutputFileURL:self.outputURL recordingDelegate:self];
    }
}

- (CMTime)recordedDuration {
    return self.movieOutput.recordedDuration;
}

- (NSURL *)uniqueURL {
    // Listing 6.14
    // 7
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *dirPath = [fileManager temporaryDirectoryWithTemplateString:@"kamera.test"];
    
    if(dirPath) {
        NSString *filePath = [dirPath stringByAppendingPathComponent:@"kemera_movie.mov"];
        return [NSURL fileURLWithPath:filePath];
    }
    
    return nil;
}

- (void)stopRecording {
    // Listing 6.14
    // 9
    
    if([self isRecording]) {
        [self.movieOutput stopRecording];
    }
}

#pragma mark - AVCaptureFileOutputRecordingDelegate

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput
didFinishRecordingToOutputFileAtURL:(NSURL *)outputFileURL
      fromConnections:(NSArray *)connections
                error:(NSError *)error {

    // Listing 6.15
    // 1
    if(error) {
        [self.delegate mediaCaptureFailedWithError:error];
    } else {
        [self writeVideoToAssetsLibrary:[self.outputURL copy]];
    }
    
    self.outputURL = nil;

}

- (void)writeVideoToAssetsLibrary:(NSURL *)videoURL {
    // Listing 6.15
    // 2
    ALAssetsLibrary *library = [ALAssetsLibrary new];
    
    // 3
    if([library videoAtPathIsCompatibleWithSavedPhotosAlbum:videoURL]) {
        ALAssetsLibraryWriteVideoCompletionBlock completionBlock;
        
        // 4
        completionBlock = ^(NSURL *asssetURL, NSError *error) {
            if(error) {
                [self.delegate assetLibraryWriteFailedWithError:error];
            } else {
                [self generateThumbnailForVideoAtURL:videoURL];
            }
        };
        
        // 8
        [library writeVideoAtPathToSavedPhotosAlbum:videoURL completionBlock:completionBlock];
    }
}

- (void)generateThumbnailForVideoAtURL:(NSURL *)videoURL {
    // Listing 6.15
    
    dispatch_async(self.videoQueue, ^{
        AVAsset *asset = [AVAsset assetWithURL:videoURL];
        
        // 5
        AVAssetImageGenerator *imageGenerator = [AVAssetImageGenerator assetImageGeneratorWithAsset:asset];
        imageGenerator.maximumSize = CGSizeMake(100.0f, 0.0f);
        imageGenerator.appliesPreferredTrackTransform = YES;
        
        // 6
        CGImageRef imageRef = [imageGenerator copyCGImageAtTime:kCMTimeZero actualTime:NULL error:nil];
        
        UIImage *image = [UIImage imageWithCGImage:imageRef];
        CGImageRelease(imageRef);
        
        // 7
        dispatch_async(dispatch_get_main_queue(), ^{
            [self postThumbnailNotifification:image];
        });
    });
    
}


@end

