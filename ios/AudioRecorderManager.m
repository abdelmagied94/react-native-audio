//
//  AudioRecorderManager.m
//  AudioRecorderManager
//
//  Created by Joshua Sierles on 15/04/15.
//  Copyright (c) 2015 Joshua Sierles. All rights reserved.
//

#import "AudioRecorderManager.h"
#import <React/RCTConvert.h>
#import <React/RCTUtils.h>
#import <React/RCTEventDispatcher.h>
#import <AVFoundation/AVFoundation.h>

NSString *const Tag = @"AudioRecorderManager";

NSString *const InvalidStateError = @"INVALID_STATE";
NSString *const FailedToConfigureRecorderError = @"FAILED_TO_CONFIGURE_MEDIA_RECORDER";
NSString *const FailedToPrepareRecorderError = @"FAILED_TO_PREPARE_RECORDER";
NSString *const RecorderNotPreparedError = @"RECORDER_NOT_PREPARED";
NSString *const FailedToActivateAudioSession = @"FAILED_TO_ACTIVATE_AUDIO_SESSION";
NSString *const NoRecordDataFoundError = @"NO_RECORD_DATA_FOUND";
NSString *const NoAccessToWriteToDirectoryError = @"NO_ACCESS_TO_WRITE_TO_DIRECTORY";
NSString *const AudioEncodingError = @"AUDIO_ENCODING_ERROR";
NSString *const CleanUpError = @"CLEAN_UP_ERROR";

NSString *const AudioLowQuality = @"Low";
NSString *const AudioMediumQuality = @"Medium";
NSString *const AudioHighQuality = @"High";

NSString *const LpcmAudioEncoding = @"lpcm";
NSString *const Ima4AudioEncoding = @"ima4";
NSString *const AacAudioEncoding = @"aac";
NSString *const Mac3AudioEncoding = @"MAC3";
NSString *const Mac6AudioEncoding = @"MAC6";
NSString *const UlawAudioEncoding = @"ulaw";
NSString *const AlawAudioEncoding = @"alaw";
NSString *const Mp1AudioEncoding = @"mp1";
NSString *const Mp2AudioEncoding = @"mp2";
NSString *const AlacAudioEncoding = @"alac";
NSString *const AmrAudioEncoding = @"amr";
NSString *const FlacAudioEncoding = @"flac";
NSString *const OpusAudioEncoding = @"opus";

NSString *const AudioRecorderEventProgress = @"recordingProgress";
NSString *const AudioRecorderEventFinished = @"recordingFinished";
NSString *const AudioRecorderEventError = @"recordingError";

NSString *const PermissionsGranted = @"granted";
NSString *const PermissionsDenied = @"denied";
NSString *const PermissionsUndetermined = @"undetermined";

@implementation AudioRecorderManager {

  AVAudioRecorder *_audioRecorder;

  NSTimeInterval _currentTime;
  CADisplayLink *_progressUpdateTimer;
  NSTimeInterval _maxRecordingDuration;
  NSTimeInterval _progressUpdateInterval;
  BOOL _meteringEnabled;
  BOOL _includeBase64;
  BOOL _destroyNextStoppedRecording;
}

RCT_EXPORT_MODULE();

- (NSArray<NSString *> *)supportedEvents
{
  return @[AudioRecorderEventProgress, AudioRecorderEventFinished, AudioRecorderEventError];
}

+ (BOOL)requiresMainQueueSetup {
  return YES;
}

- (void)dealloc {
  [self reset];
}

- (void)sendProgressUpdate {
  if (_audioRecorder == nil || !_audioRecorder.isRecording || _audioRecorder.currentTime - _currentTime < _progressUpdateInterval) {
    return;
  }
  
  
  _currentTime = _audioRecorder.currentTime;

  NSMutableDictionary *body = [[NSMutableDictionary alloc] init];
  [body setObject:[self currentRecordingFile] forKey:@"path"];
  [body setObject:[NSNumber numberWithFloat:_currentTime] forKey:@"currentTime"];
  
  if (_meteringEnabled) {
    [_audioRecorder updateMeters];
    float _currentMetering = [_audioRecorder averagePowerForChannel: 0];
    [body setObject:[NSNumber numberWithFloat:_currentMetering] forKey:@"currentMetering"];

    float _currentPeakMetering = [_audioRecorder peakPowerForChannel: 0];
    [body setObject:[NSNumber numberWithFloat:_currentPeakMetering] forKey:@"currentPeakMetering"];
  }
  
  [self sendEventWithName:AudioRecorderEventProgress body:body];
}

- (void)stopProgressTimer {
  if (_progressUpdateTimer) {
    _progressUpdateTimer.paused = YES;
    [_progressUpdateTimer invalidate];
  }
}

- (void)startProgressTimer {
  [self stopProgressTimer];
  
  _progressUpdateTimer = [CADisplayLink displayLinkWithTarget:self selector:@selector(sendProgressUpdate)];
  [_progressUpdateTimer addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)audioRecorderDidFinishRecording:(AVAudioRecorder *)recorder successfully:(BOOL)flag {
  if (![recorder isEqual:_audioRecorder]) {
    [self clean:recorder];
    return;
  }
  
  NSURL *audioFileURL = [recorder url];
  
  if (!flag || !audioFileURL) {
    [self reset];
    [self stopAudioSession];
    
    [self sendEventWithName:AudioRecorderEventError body:@{
      @"path": [[recorder url] path],
      @"code": AudioEncodingError,
    }];
    
    return;
  }
  
  if (_destroyNextStoppedRecording) {
    _destroyNextStoppedRecording = NO;
    
    if (recorder) {
      if (![recorder deleteRecording]) {
        NSLog(@"%@: Failed to delete record file at path %@", Tag, [audioFileURL absoluteString]);
      }
    }
    
    return;
  }
  
  NSString *base64 = @"";
  if (_includeBase64) {
    NSData *data = [NSData dataWithContentsOfURL: audioFileURL];
    base64 = [data base64EncodedStringWithOptions:0];
  }
  NSString *audioFilePath = [audioFileURL path];
  NSString *audioFileURI = [audioFileURL absoluteString];
  uint64_t audioFileSize = 0;
  NSError *error = nil;
  NSDictionary<NSFileAttributeKey, id> *audioFileAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:audioFilePath error:&error];
  
  if (audioFileAttributes != nil) {
    audioFileSize = [audioFileAttributes fileSize];
  } else {
    NSLog(@"%@: Failed to get file size %@", Tag, error);
  }
  
  NSTimeInterval duration = _currentTime;
  
  [self reset];
  [self stopAudioSession];
  
  [self sendEventWithName:AudioRecorderEventFinished body:@{
    @"base64":base64,
    @"duration":@(duration),
    @"path": audioFilePath,
    @"uri": audioFileURI,
    @"size": @(audioFileSize)
  }];
}

- (void)audioRecorderEncodeErrorDidOccur:(AVAudioRecorder *)recorder error:(NSError *)error {
  if (![recorder isEqual:_audioRecorder]) {
    [self clean:recorder];
    return;
  }
  
  if (error) {
    [self reset];
    [self stopAudioSession];
    
    [self sendEventWithName:AudioRecorderEventError body:@{
      @"path": [self currentRecordingFile],
      @"code": AudioEncodingError,
      @"extra": error.localizedDescription,
    }];
  }
}

- (NSString *) applicationDocumentsDirectory {
  NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
  NSString *basePath = ([paths count] > 0) ? [paths objectAtIndex:0] : nil;
  return basePath;
}

RCT_REMAP_METHOD(destroy,
         destroyWithResolver:(RCTPromiseResolveBlock)resolve
         rejecter:(__unused RCTPromiseRejectBlock)reject)
{
  _destroyNextStoppedRecording = YES;
  [self partialRest];
  resolve(nil);
}

RCT_REMAP_METHOD(prepareRecordingAtPath,
         path:(NSString *)path
         options:(NSDictionary *)options
         prepareRecordingAtPathWithResolver:(RCTPromiseResolveBlock)resolve
         rejecter:(RCTPromiseRejectBlock)reject)
{
  if (_audioRecorder && _audioRecorder.isRecording) {
    reject(InvalidStateError, @"Please call stopRecording before starting recording", nil);
    return;
  }

  NSString *quality = [options objectForKey:@"AudioQuality"];
  NSString *encoding = [options objectForKey:@"AudioEncoding"];
  NSTimeInterval maxDuration = [[options objectForKey:@"MaxDuration"] doubleValue];
  double progressUpdateInterval = [[options objectForKey:@"ProgressUpdateInterval"] doubleValue];
  BOOL meteringEnabled = [[options objectForKey:@"MeteringEnabled"] boolValue];
  BOOL measurementMode = [[options objectForKey:@"MeasurementMode"] boolValue];
  BOOL includeBase64 = [[options objectForKey:@"IncludeBase64"] boolValue];

  NSString *filePathAndDirectory = [path stringByDeletingLastPathComponent];
  NSError *error = nil;
  
  // create parent dirs if necessary
  [[NSFileManager defaultManager] createDirectoryAtPath:filePathAndDirectory withIntermediateDirectories:YES attributes:nil error:&error];
  if (error) {
    NSLog(@"%@: Create directory error: %@", Tag, error);
    reject(NoAccessToWriteToDirectoryError, [NSString stringWithFormat:@"Please ensure you have access to the specified path (/%@)", path], nil);
    return;
  }

  NSURL *audioFileURL = [NSURL fileURLWithPath:path isDirectory:false];
  NSNumber *audioEncoding = [self getAudioEncoding:encoding];
  NSNumber *audioQuality = [self getAudioQuality:quality];
  NSNumber *audioChannels = [NSNumber numberWithLong:[[options objectForKey:@"Channels"] longValue]];
  NSNumber *audioSampleRate = [NSNumber numberWithLongLong:[[options objectForKey:@"SampleRate"] longLongValue]];
  NSNumber *audioBitRate = [NSNumber numberWithLongLong:[[options objectForKey:@"AudioEncodingBitRate"] longLongValue]];
  
  _progressUpdateInterval = progressUpdateInterval / 1000.0;
  _meteringEnabled = meteringEnabled;
  _includeBase64 = includeBase64;
  _maxRecordingDuration = maxDuration / 1000.0;
  
  NSDictionary *recordSettings = [NSDictionary dictionaryWithObjectsAndKeys:
      audioQuality, AVEncoderAudioQualityKey,
      audioEncoding, AVFormatIDKey,
      audioChannels, AVNumberOfChannelsKey,
      audioSampleRate, AVSampleRateKey,
      audioBitRate, AVEncoderBitRateKey,
      nil];
  
  AVAudioSession *audioSession = [AVAudioSession sharedInstance];

  if (measurementMode) {
    [audioSession setCategory:AVAudioSessionCategoryRecord error:&error];
    
    if (!error) {
      [audioSession setMode:AVAudioSessionModeMeasurement error:&error];
    }
  } else {
    [audioSession setCategory:AVAudioSessionCategoryPlayAndRecord withOptions:AVAudioSessionCategoryOptionAllowBluetooth error:&error];
  }
  
  if (error) {
    reject(FailedToConfigureRecorderError, [NSString stringWithFormat:@"Failed to configure audio session. error: %@", error], nil);
    return;
  }

  _audioRecorder = [[AVAudioRecorder alloc]
        initWithURL:audioFileURL
        settings:recordSettings
        error:&error];

  if (error || !_audioRecorder) {
    [self reset];
    reject(FailedToConfigureRecorderError, [NSString stringWithFormat:@"Failed to initialize audio recorder with path %@. error: %@", path, error], nil);
    return;
  }
    
  _audioRecorder.meteringEnabled = _meteringEnabled;
  _audioRecorder.delegate = self;

  if ([_audioRecorder prepareToRecord] == NO) {
    [self reset];
    
    reject(FailedToPrepareRecorderError, [NSString stringWithFormat:@"Failed to prepare recorder with path %@. error: %@", path, error], nil);
  } else {
    _destroyNextStoppedRecording = NO;
    resolve(path);
  }
}

RCT_REMAP_METHOD(startRecording,
          startRecordingWithResolver:(RCTPromiseResolveBlock)resolve
          rejecter:(RCTPromiseRejectBlock)reject) {
  if (_audioRecorder == nil) {
    reject(RecorderNotPreparedError, @"Please call prepareRecordingAtPath(or prepareRecording) before starting recording", nil);
    return;
  }
  
  [self startProgressTimer];
  
  NSError *error = nil;
  [[AVAudioSession sharedInstance] setActive:YES error:&error];
  
  if (error) {
    reject(FailedToActivateAudioSession, [NSString stringWithFormat:@"Could not set audio session active, error: %@", error], nil);
    return;
  }
  
  if (_maxRecordingDuration > 0) {
    [_audioRecorder recordForDuration:_maxRecordingDuration];
  } else {
    [_audioRecorder record];
  }
  
  resolve([self currentRecordingFile]);
}

RCT_REMAP_METHOD(stopRecording,
          stopRecordingWithResolver:(RCTPromiseResolveBlock)resolve
          rejecter:(__unused RCTPromiseRejectBlock)reject)
{
  [self partialRest];
  resolve(nil);
}

RCT_EXPORT_METHOD(pauseRecording)
{
  if (_audioRecorder.isRecording) {
    [_audioRecorder pause];
  }
}

RCT_EXPORT_METHOD(resumeRecording)
{
  if (!_audioRecorder.isRecording) {
    [_audioRecorder record];
  }
}

RCT_EXPORT_METHOD(checkAuthorizationStatus:(RCTPromiseResolveBlock)resolve reject:(__unused RCTPromiseRejectBlock)reject)
{
  AVAudioSessionRecordPermission permissionStatus = [[AVAudioSession sharedInstance] recordPermission];
  switch (permissionStatus) {
    case AVAudioSessionRecordPermissionUndetermined:
      resolve(PermissionsUndetermined);
    break;
    case AVAudioSessionRecordPermissionDenied:
      resolve(PermissionsDenied);
      break;
    case AVAudioSessionRecordPermissionGranted:
      resolve(PermissionsGranted);
      break;
    default:
      reject(RCTErrorUnspecified, nil, RCTErrorWithMessage(@("Error checking device authorization status.")));
      break;
  }
}

RCT_EXPORT_METHOD(requestAuthorization:(RCTPromiseResolveBlock)resolve
          rejecter:(__unused RCTPromiseRejectBlock)reject)
{
  [[AVAudioSession sharedInstance] requestRecordPermission:^(BOOL granted) {
    if(granted) {
      resolve(@YES);
    } else {
      resolve(@NO);
    }
  }];
}

RCT_EXPORT_METHOD(cleanPath:(NSString *)path
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {

  if (!path) {
    reject(CleanUpError, @"Error invalid path", nil);
    return;
  }
  
  BOOL isDir = NO;
  BOOL isExist = [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir];
  
  if (!isExist) {
    resolve(nil);
    return;
  }
  
  NSError *error = isDir ? [self deleteDirectory:path] : [self deleteFile:path];
  
  if (error) {
    reject(CleanUpError, [NSString stringWithFormat:@"Failed to delete path %@", path], error);
  } else {
    resolve(nil);
  }
}

- (void) partialRest {
  [self stopProgressTimer];
  [self clean:_audioRecorder];
}

- (void) reset {
  [self partialRest];
  
  _audioRecorder = nil;
  _progressUpdateTimer = nil;
  _maxRecordingDuration = 0;
  _currentTime = 0;
}

- (void) stopAudioSession {
  NSError *error;
  [[AVAudioSession sharedInstance] setActive:NO withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:&error];
  
  if (error) {
    NSLog(@"%@: Could not deactivate current audio session. Error: %@", Tag, error);
  }
}

- (void) clean:(AVAudioRecorder *)recorder {
  if (recorder) {
    [recorder stop];
  }
}

- (NSString *)currentRecordingFile {
  if (!_audioRecorder) {
    return nil;
  }
  
  NSURL* url = [_audioRecorder url];
  return url ? [url path] : nil;
}

- (NSString *)getPathForDirectory:(int)directory {
  NSArray *paths = NSSearchPathForDirectoriesInDomains(directory, NSUserDomainMask, YES);
  return [paths firstObject];
}

- (NSDictionary *)constantsToExport {
  return @{
    @"MainBundlePath": [[NSBundle mainBundle] bundlePath],
    @"CachesDirectoryPath": [self getPathForDirectory:NSCachesDirectory],
    @"DocumentDirectoryPath": [self getPathForDirectory:NSDocumentDirectory],
    @"LibraryDirectoryPath": [self getPathForDirectory:NSLibraryDirectory],
    @"InvalidState": InvalidStateError,
    @"FailedToConfigureRecorder": FailedToConfigureRecorderError,
    @"FailedToPrepareRecorder": FailedToPrepareRecorderError,
    @"RecorderNotPrepared": RecorderNotPreparedError,
    @"NoRecordDataFound": NoRecordDataFoundError,
    @"NoAccessToWriteToDirectory": NoAccessToWriteToDirectoryError,
    @"FailedToEncodeAudio": AudioEncodingError,
    @"CleanUpError": CleanUpError,
    @"AudioLowQuality": AudioLowQuality,
    @"AudioMediumQuality": AudioMediumQuality,
    @"AudioHighQuality": AudioHighQuality,
    @"LpcmAudioEncoding": LpcmAudioEncoding,
    @"Ima4AudioEncoding": Ima4AudioEncoding,
    @"AacAudioEncoding": AacAudioEncoding,
    @"Mac3AudioEncoding": Mac3AudioEncoding,
    @"Mac6AudioEncoding": Mac6AudioEncoding,
    @"UlawAudioEncoding": UlawAudioEncoding,
    @"AlawAudioEncoding": AlawAudioEncoding,
    @"Mp1AudioEncoding": Mp1AudioEncoding,
    @"Mp2AudioEncoding": Mp2AudioEncoding,
    @"AlacAudioEncoding": AlacAudioEncoding,
    @"AmrAudioEncoding": AmrAudioEncoding,
    @"FlacAudioEncoding": FlacAudioEncoding,
    @"OpusAudioEncoding": OpusAudioEncoding,
  };
}

- (NSNumber *) getAudioQuality:(NSString *)quality {
  if (quality != nil) {
    if ([quality  isEqual: AudioLowQuality]) {
      return [NSNumber numberWithInt:AVAudioQualityLow];
    } else if ([quality  isEqual: AudioMediumQuality]) {
      return [NSNumber numberWithInt:AVAudioQualityMedium];
    } else if ([quality  isEqual: AudioHighQuality]) {
      return [NSNumber numberWithInt:AVAudioQualityHigh];
    }
  }
  
  NSLog(@"%@: Invalid audio quality. Revert to use hight quality one", Tag);
  
  return [NSNumber numberWithInt:AVAudioQualityHigh];
}

- (NSNumber *) getAudioEncoding:(NSString *)encoding {
  if (encoding != nil) {
    if ([encoding  isEqual: LpcmAudioEncoding]) {
      return [NSNumber numberWithInt:kAudioFormatLinearPCM];
    } else if ([encoding  isEqual: Ima4AudioEncoding]) {
      return [NSNumber numberWithInt:kAudioFormatAppleIMA4];
    } else if ([encoding  isEqual: AacAudioEncoding]) {
      return [NSNumber numberWithInt:kAudioFormatMPEG4AAC];
    } else if ([encoding  isEqual: Mac3AudioEncoding]) {
      return [NSNumber numberWithInt:kAudioFormatMACE3];
    } else if ([encoding  isEqual: Mac6AudioEncoding]) {
      return [NSNumber numberWithInt:kAudioFormatMACE6];
    } else if ([encoding  isEqual: UlawAudioEncoding]) {
      return [NSNumber numberWithInt:kAudioFormatULaw];
    } else if ([encoding  isEqual: AlawAudioEncoding]) {
      return [NSNumber numberWithInt:kAudioFormatALaw];
    } else if ([encoding  isEqual: Mp1AudioEncoding]) {
      return [NSNumber numberWithInt:kAudioFormatMPEGLayer1];
    } else if ([encoding  isEqual: Mp2AudioEncoding]) {
      return [NSNumber numberWithInt:kAudioFormatMPEGLayer2];
    } else if ([encoding  isEqual: AlacAudioEncoding]) {
      return [NSNumber numberWithInt:kAudioFormatAppleLossless];
    } else if ([encoding  isEqual: AmrAudioEncoding]) {
      return [NSNumber numberWithInt:kAudioFormatAMR];
    } else if ([encoding  isEqual: FlacAudioEncoding]) {
      if (@available(iOS 11, *)) return [NSNumber numberWithInt:kAudioFormatFLAC];
    } else if ([encoding  isEqual: OpusAudioEncoding]) {
      if (@available(iOS 11, *)) return [NSNumber numberWithInt:kAudioFormatOpus];
    }
  }
  
  NSLog(@"%@: Invalid audio encoding. Revert to use default encoding `aac`", Tag);
  
  return [NSNumber numberWithInt:kAudioFormatMPEG4AAC];
}

- (NSError *) deleteDirectory:(NSString *)directoryPath {
  NSError *error;
  NSArray *directoryFiles = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:directoryPath error:&error];
  
  if (error) {
    return error;
  }

  for (NSString *filename in directoryFiles) {
    NSError *fileError;
    BOOL deleted = [[NSFileManager defaultManager] removeItemAtPath:[directoryPath stringByAppendingPathComponent:filename] error:&fileError];

    if (!deleted) {
      error = fileError;
    }
  }
  
  return error;
}

- (NSError *) deleteFile:(NSString *)filePath {
  NSError *error;
  BOOL deleted = [[NSFileManager defaultManager] removeItemAtPath:filePath error:&error];

  if (!deleted) {
    return error;
  } else {
    return nil;
  }
}

@end
