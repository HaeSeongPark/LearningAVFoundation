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
    
    return NO;
}

- (void)exposeAtPoint:(CGPoint)point {

    // Listing 6.9

}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context {

    // Listing 6.9

}

- (void)resetFocusAndExposureModes {

    // Listing 6.10

}



#pragma mark - Flash and Torch Modes

- (BOOL)cameraHasFlash {

    // Listing 6.11
    
    return NO;
}

- (AVCaptureFlashMode)flashMode {

    // Listing 6.11
    
    return 0;
}

- (void)setFlashMode:(AVCaptureFlashMode)flashMode {

    // Listing 6.11

}

- (BOOL)cameraHasTorch {

    // Listing 6.11
    
    return NO;
}

- (AVCaptureTorchMode)torchMode {

    // Listing 6.11
    
    return 0;
}

- (void)setTorchMode:(AVCaptureTorchMode)torchMode {

    // Listing 6.11
    
}


#pragma mark - Image Capture Methods

- (void)captureStillImage {

    // Listing 6.12

}

- (AVCaptureVideoOrientation)currentVideoOrientation {
    
    // Listing 6.12
    
    // Listing 6.13
    
    return 0;
}


- (void)writeImageToAssetsLibrary:(UIImage *)image {

    // Listing 6.13
    
}

- (void)postThumbnailNotifification:(UIImage *)image {

    // Listing 6.13
    
}

#pragma mark - Video Capture Methods

- (BOOL)isRecording {

    // Listing 6.14
    
    return NO;
}

- (void)startRecording {

    // Listing 6.14

}

- (CMTime)recordedDuration {
    return self.movieOutput.recordedDuration;
}

- (NSURL *)uniqueURL {


    // Listing 6.14
    
    return nil;
}

- (void)stopRecording {

    // Listing 6.14
}

#pragma mark - AVCaptureFileOutputRecordingDelegate

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput
didFinishRecordingToOutputFileAtURL:(NSURL *)outputFileURL
      fromConnections:(NSArray *)connections
                error:(NSError *)error {

    // Listing 6.15

}

- (void)writeVideoToAssetsLibrary:(NSURL *)videoURL {

    // Listing 6.15
    
}

- (void)generateThumbnailForVideoAtURL:(NSURL *)videoURL {

    // Listing 6.15
    
}


@end

