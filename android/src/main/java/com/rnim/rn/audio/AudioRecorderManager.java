package com.rnim.rn.audio;

import android.Manifest;

import com.facebook.react.bridge.ReactApplicationContext;
import com.facebook.react.bridge.ReactContextBaseJavaModule;
import com.facebook.react.bridge.ReactMethod;

import com.facebook.react.bridge.Arguments;
import com.facebook.react.bridge.Promise;
import com.facebook.react.bridge.ReadableMap;
import com.facebook.react.bridge.WritableMap;

import com.facebook.react.modules.core.DeviceEventManagerModule;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileNotFoundException;
import java.io.IOException;
import java.io.InputStream;
import java.util.HashMap;
import java.util.Map;
import java.util.Timer;
import java.util.TimerTask;

import android.app.Activity;
import android.content.pm.PackageManager;
import android.os.Build;
import android.os.Environment;
import android.media.MediaRecorder;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;

import android.util.Base64;
import android.util.Log;

import java.io.FileInputStream;

class AudioRecorderManager extends ReactContextBaseJavaModule implements MediaRecorder.OnErrorListener, MediaRecorder.OnInfoListener {

  private static final String TAG = "ReactNativeAudio";

  private static final String AudioRecorderEventProgress = "recordingProgress";
  private static final String AudioRecorderEventFinished = "recordingFinished";
  private static final String AudioRecorderEventError = "recordingError";

  private static final String DocumentDirectoryPath = "DocumentDirectoryPath";
  private static final String PicturesDirectoryPath = "PicturesDirectoryPath";
  private static final String MainBundlePath = "MainBundlePath";
  private static final String CachesDirectoryPath = "CachesDirectoryPath";
  private static final String LibraryDirectoryPath = "LibraryDirectoryPath";
  private static final String MusicDirectoryPath = "MusicDirectoryPath";
  private static final String DownloadsDirectoryPath = "DownloadsDirectoryPath";

  private static final String InvalidStateError = "INVALID_STATE";
  private static final String AlreadyRecordingError = "ALREADY_RECORDING_ERROR";
  private static final String FailedToConfigureRecorderError = "FAILED_TO_CONFIGURE_MEDIA_RECORDER";
  private static final String FailedToPrepareRecorderError = "FAILED_TO_PREPARE_RECORDER";
  private static final String RecorderNotPreparedError = "RECORDER_NOT_PREPARED";
  private static final String NoRecordDataFoundError = "NO_RECORD_DATA_FOUND";
  private static final String MethodNotAvailableError = "METHOD_NOT_AVAILABLE_ERROR";
  private static final String ReactContextNotInitializedError = "REACT_CONTEXT_NOT_INITIALIZED";
  private static final String NoAccessToWriteToDirectoryError = "NO_ACCESS_TO_WRITE_TO_DIRECTORY";
  private static final String RecorderServerDiedError = "RECORDER_SERVER_DIED";
  private static final String RecorderUnknownError = "RECORDER_UNKNOWN_ERROR";
  private static final String CleanUpError = "CLEAN_UP_ERROR";

  private static final String AacAudioEncoding = "aac";
  private static final String AacEldAudioEncoding = "aac_eld";
  private static final String AmrNbAudioEncoding = "amr_nb";
  private static final String AmrWbAudioEncoding = "amr_wb";
  private static final String HeAacAudioEncoding = "he_aac";
  private static final String VorbisAudioEncoding = "vorbis";

  private static final String Mpeg4AudioOutputFormat = "mpeg_4";
  private static final String AacAdtsAudioOutputFormat = "aac_adts";
  private static final String AmrNbAudioOutputFormat = "amr_nb";
  private static final String AmrWbAudioOutputFormat = "amr_wb";
  private static final String ThreeGppAudioOutputFormat = "three_gpp";
  private static final String WebmAudioOutputFormat = "webm";
  private static final String Mpeg2TsAudioOutputFormat = "mpeg_2_ts";

  private static final String PERMISSIONS_GRANTED = "granted";
  private static final String PERMISSIONS_DENIED = "denied";
  private static final String PERMISSIONS_NEVER_ASK_AGAIN = "never_ask_again";

  private MediaRecorder recorder = null;
  private String currentOutputFilePath = null;
  private int currentMaxDuration = 0;
  private boolean isRecording = false;
  private boolean isPaused = false;
  private boolean includeBase64 = false;
  private Timer timer;
  private StopWatch stopWatch;
  private boolean meteringEnabled = false;
  private int progressUpdateInterval = 1000;	// 1 second

  public AudioRecorderManager(ReactApplicationContext reactContext) {
    super(reactContext);
    stopWatch = new StopWatch();
  }

  @Override
  public Map<String, Object> getConstants() {
    Map<String, Object> constants = new HashMap<>();
    constants.put(DocumentDirectoryPath, this.getReactApplicationContext().getFilesDir().getAbsolutePath());
    constants.put(PicturesDirectoryPath, Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES).getAbsolutePath());
    constants.put(MainBundlePath, "");
    constants.put(CachesDirectoryPath, this.getReactApplicationContext().getCacheDir().getAbsolutePath());
    constants.put(LibraryDirectoryPath, "");
    constants.put(MusicDirectoryPath, Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MUSIC).getAbsolutePath());
    constants.put(DownloadsDirectoryPath, Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS).getAbsolutePath());

    constants.put("InvalidState", InvalidStateError);
    constants.put("FailedToConfigureRecorder", FailedToConfigureRecorderError);
    constants.put("FailedToPrepareRecorder", FailedToPrepareRecorderError);
    constants.put("RecorderNotPrepared", RecorderNotPreparedError);
    constants.put("NoRecordDataFound", NoRecordDataFoundError);
    constants.put("MethodNotAvailable", MethodNotAvailableError);
    constants.put("ReactContextNotInitialized", ReactContextNotInitializedError);
    constants.put("NoAccessToWriteToDirectory", NoAccessToWriteToDirectoryError);
    constants.put("RecorderServerDied", RecorderServerDiedError);
    constants.put("UnknownError", RecorderUnknownError);
    constants.put("AlreadyRecording", AlreadyRecordingError);
    
    constants.put("AacAudioEncoding", AacAudioEncoding);
    constants.put("AacEldAudioEncoding", AacEldAudioEncoding);
    constants.put("AmrNbAudioEncoding", AmrNbAudioEncoding);
    constants.put("AmrWbAudioEncoding", AmrWbAudioEncoding);
    constants.put("HeAacAudioEncoding", HeAacAudioEncoding);
    constants.put("VorbisAudioEncoding", VorbisAudioEncoding);

    constants.put("Mpeg4AudioOutputFormat", Mpeg4AudioOutputFormat);
    constants.put("AacAdtsAudioOutputFormat", AacAdtsAudioOutputFormat);
    constants.put("AmrNbAudioOutputFormat", AmrNbAudioOutputFormat);
    constants.put("AmrWbAudioOutputFormat", AmrWbAudioOutputFormat);
    constants.put("ThreeGppAudioOutputFormat", ThreeGppAudioOutputFormat);
    constants.put("WebmAudioOutputFormat", WebmAudioOutputFormat);
    constants.put("Mpeg2TsAudioOutputFormat", Mpeg2TsAudioOutputFormat);

    return constants;
  }

  @NonNull
  @Override
  public String getName() {
    return "AudioRecorderManager";
  }

  @ReactMethod
  public void checkAuthorizationStatus(Promise promise) {
    Activity activity = getCurrentActivity();

    if (activity == null) {
      promise.reject(ReactContextNotInitializedError, "No RN activity is active");
      return;
    }

    if (ContextCompat.checkSelfPermission(activity,
        Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
      promise.resolve(PERMISSIONS_GRANTED);
    } else if (ActivityCompat.shouldShowRequestPermissionRationale(activity, Manifest.permission.RECORD_AUDIO)) {
      promise.resolve(PERMISSIONS_DENIED);
    } else {
      promise.resolve(PERMISSIONS_NEVER_ASK_AGAIN);
    }
  }

  @ReactMethod
  public void prepareRecordingAtPath(String recordingPath, ReadableMap recordingSettings, Promise promise) {
    if (isRecording){
      logAndRejectPromise(promise, InvalidStateError, "Call stopRecording before starting new recording");
      return;
    }

    if (recordingPath == null) {
      logAndRejectPromise(promise, NoAccessToWriteToDirectoryError, "Invalid recording path");
      return;
    }

    File destFile = new File(recordingPath);
    if (!makeDir(destFile.getParentFile())) {
      logAndRejectPromise(promise, NoAccessToWriteToDirectoryError, "Make sure you have access to the recording path (" + recordingPath + ")");
      return;
    }

    // Release old recorder in case if `prepare` function called multiple times in sequence
    // without recording
    if (recorder != null) {
      reset();
    }

    recorder = new MediaRecorder();
    recorder.setOnErrorListener(this);
    recorder.setOnInfoListener(this);

    try {
      recorder.setAudioSource(recordingSettings.getInt("AudioSource"));
      int outputFormat = getOutputFormatFromString(recordingSettings.getString("OutputFormat"));
      recorder.setOutputFormat(outputFormat);

      currentMaxDuration = recordingSettings.getInt("MaxDuration");
      recorder.setMaxDuration(currentMaxDuration);

      int audioEncoder = getAudioEncoderFromString(recordingSettings.getString("AudioEncoding"));
      recorder.setAudioEncoder(audioEncoder);
      recorder.setAudioSamplingRate(recordingSettings.getInt("SampleRate"));
      recorder.setAudioChannels(recordingSettings.getInt("Channels"));
      recorder.setAudioEncodingBitRate(recordingSettings.getInt("AudioEncodingBitRate"));
      recorder.setOutputFile(destFile.getPath());
      includeBase64 = recordingSettings.getBoolean("IncludeBase64");
      meteringEnabled = recordingSettings.getBoolean(("MeteringEnabled"));
      progressUpdateInterval = recordingSettings.getInt("ProgressUpdateInterval");
    } catch(final Exception e) {
      reset();
      logAndRejectPromise(promise, FailedToConfigureRecorderError, "Make sure you've added RECORD_AUDIO permission to your AndroidManifest.xml file " + e.getMessage());
      return;
    }

    try {
      recorder.prepare();
      currentOutputFilePath = recordingPath;
      promise.resolve(currentOutputFilePath);
    } catch (final Exception e) {
      reset();
      logAndRejectPromise(promise, FailedToPrepareRecorderError, "Preparing recorder at path (" + recordingPath + ") failed with error: " + e.getMessage());
    }
  }

  @ReactMethod
  public void destroy(Promise promise) {
    reset();
    promise.resolve(null);
  }

  @ReactMethod
  public void startRecording(Promise promise){
    if (recorder == null){
      logAndRejectPromise(promise, RecorderNotPreparedError, "Call prepareRecordingAtPath before starting recording");
      return;
    }
    if (isRecording){
      logAndRejectPromise(promise, InvalidStateError, "Call stopRecording before starting new recording");
      return;
    }
    
    try {
      recorder.start();
    } catch (IllegalStateException e) {
      logAndRejectPromise(promise, AlreadyRecordingError, "Recorder is already running");
      return;
    }

    stopWatch.reset();
    stopWatch.start();
    isRecording = true;
    isPaused = false;

    startTimer();

    promise.resolve(currentOutputFilePath);
  }

  @ReactMethod
  public void stopRecording(Promise promise){
    if (!isRecording){
      logAndRejectPromise(promise, InvalidStateError, "Prepare and start recording before stopping recording");
      return;
    }

    double duration = stopWatch.getTimeSeconds();

    try {
      recorder.stop();
    } catch(final IllegalStateException e) {
      reset();
      logAndRejectPromise(promise, InvalidStateError, "Prepare and start recording before stopping recording");
      return;
    } catch (final RuntimeException e) {
      // https://developer.android.com/reference/android/media/MediaRecorder.html#stop()
      reset();
      logAndRejectPromise(promise, NoRecordDataFoundError, "No valid audio data received. You may be using a device that can't record audio.");
      return;
    }

    promise.resolve(currentOutputFilePath);
    recordingDidFinished(duration);
  }

  @ReactMethod
  public void pauseRecording(Promise promise) {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) {
      logAndRejectPromise(promise, MethodNotAvailableError, "Method not available on this version of Android.");
      return;
    }

    if (recorder == null || !isRecording) {
      logAndRejectPromise(promise, InvalidStateError, "Prepare or start recorder before pausing");
      return;
    }

    if (!isPaused) {
      try {
        recorder.pause();
        stopWatch.stop();
      } catch (final IllegalStateException e) {
        e.printStackTrace();
        logAndRejectPromise(promise, InvalidStateError, "Start recorder before pausing");
        return;
      }
    }

    isPaused = true;
    promise.resolve(null);
  }

  @ReactMethod
  public void resumeRecording(Promise promise) {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) {
      logAndRejectPromise(promise, MethodNotAvailableError, "Method not available on this version of Android.");
      return;
    }

    if (recorder == null || !isRecording) {
      logAndRejectPromise(promise, InvalidStateError, "Prepare or start recorder before resuming");
      return;
    }

    if (isPaused) {
      try {
        recorder.resume();
        stopWatch.start();
      } catch (IllegalStateException e) {
        e.printStackTrace();
        logAndRejectPromise(promise, InvalidStateError, "Start recorder before resuming");
        return;
      }
    }

    isPaused = false;
    promise.resolve(null);
  }

  @ReactMethod
  public void cleanPath(String path, Promise promise) {
    boolean deleted = deletePath(path);

    if (deleted) {
      promise.resolve(null);
    } else {
      promise.reject(CleanUpError, "Failed to delete path " + path);
    }
  }

  @Override
  public void onError(MediaRecorder mediaRecorder, int what, int extra) {
    if (!mediaRecorder.equals(this.recorder)) {
      release(mediaRecorder);
      return;
    }

    WritableMap data = Arguments.createMap();
    data.putString("code", what == MediaRecorder.MEDIA_ERROR_SERVER_DIED ? RecorderServerDiedError : RecorderUnknownError);
    data.putString("path", currentOutputFilePath);
    data.putInt("extra", extra);

    reset();

    sendEvent(AudioRecorderEventError, data);
  }

  @Override
  public void onCatalystInstanceDestroy() {
    reset();
  }

  @Override
  public void onInfo(MediaRecorder mediaRecorder, int what, int extra) {
    if (what != MediaRecorder.MEDIA_RECORDER_INFO_MAX_DURATION_REACHED) {
      return;
    }

    if (!mediaRecorder.equals(this.recorder) || currentMaxDuration == 0) {
      release(mediaRecorder);
      return;
    }

    recordingDidFinished(currentMaxDuration / 1000d);
  }

  private void recordingDidFinished(double duration) {
    WritableMap result = Arguments.createMap();
    result.putString("path", currentOutputFilePath);
    result.putString("uri", "file://" + currentOutputFilePath);
    result.putDouble("duration", duration);
    result.putInt("size", (int) new File(currentOutputFilePath).length());

    String base64 = "";
    if (includeBase64) {
      try {
        InputStream inputStream = new FileInputStream(currentOutputFilePath);
        byte[] bytes;
        byte[] buffer = new byte[8192];
        int bytesRead;
        ByteArrayOutputStream output = new ByteArrayOutputStream();

        while ((bytesRead = inputStream.read(buffer)) != -1) {
          output.write(buffer, 0, bytesRead);
        }

        bytes = output.toByteArray();
        base64 = Base64.encodeToString(bytes, Base64.DEFAULT);
      } catch (final FileNotFoundException e) {
        base64 = "";
        Log.e(TAG, "Failed to find file at path " + currentOutputFilePath);
      } catch (IOException e) {
        base64 = "";
        Log.e(TAG, "Failed to parse file at path " + currentOutputFilePath);
      }
    }

    if (!base64.isEmpty()) {
      result.putString("base64", base64);
    }

    reset(false);

    sendEvent(AudioRecorderEventFinished, result);
  }

  private int getAudioEncoderFromString(String audioEncoder) {
    switch (audioEncoder) {
      case AacAudioEncoding:
        return MediaRecorder.AudioEncoder.AAC;
      case AacEldAudioEncoding:
        return MediaRecorder.AudioEncoder.AAC_ELD;
      case AmrNbAudioEncoding:
        return MediaRecorder.AudioEncoder.AMR_NB;
      case AmrWbAudioEncoding:
        return MediaRecorder.AudioEncoder.AMR_WB;
      case HeAacAudioEncoding:
        return MediaRecorder.AudioEncoder.HE_AAC;
      case VorbisAudioEncoding:
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
          return MediaRecorder.AudioEncoder.VORBIS;
        }
      default:
        Log.d(TAG, "INVALID_AUDIO_ENCODER: Using MediaRecorder.AudioEncoder.DEFAULT instead of "+audioEncoder+": "+MediaRecorder.AudioEncoder.DEFAULT);
        return MediaRecorder.AudioEncoder.DEFAULT;
    }
  }

  private int getOutputFormatFromString(String outputFormat) {
    switch (outputFormat) {
      case Mpeg4AudioOutputFormat:
        return MediaRecorder.OutputFormat.MPEG_4;
      case AacAdtsAudioOutputFormat:
        return MediaRecorder.OutputFormat.AAC_ADTS;
      case AmrNbAudioOutputFormat:
        return MediaRecorder.OutputFormat.AMR_NB;
      case AmrWbAudioOutputFormat:
        return MediaRecorder.OutputFormat.AMR_WB;
      case ThreeGppAudioOutputFormat:
        return MediaRecorder.OutputFormat.THREE_GPP;
      case WebmAudioOutputFormat:
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
          return MediaRecorder.OutputFormat.WEBM;
        }
      case Mpeg2TsAudioOutputFormat:
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
          return MediaRecorder.OutputFormat.MPEG_2_TS;
        }
      default:
        Log.d(TAG, "INVALID_OUTPUT_FORMAT: Using MediaRecorder.OutputFormat.DEFAULT : " + MediaRecorder.OutputFormat.DEFAULT);
        return MediaRecorder.OutputFormat.DEFAULT;
    }
  }

  private void startTimer(){
    timer = new Timer();
    timer.scheduleAtFixedRate(new TimerTask() {
      @Override
      public void run() {
        if (!isPaused) {
          WritableMap body = Arguments.createMap();

          if (meteringEnabled) {
            int maxAmplitude = 0;
            if (recorder != null) {
              maxAmplitude = recorder.getMaxAmplitude();
            }

            double dB = -160;
            double maxAudioSize = 32767d;

            if (maxAmplitude > 0) {
              dB = 20 * Math.log10(maxAmplitude / maxAudioSize);
            }

            body.putInt("currentMetering", (int) dB);
          }

          body.putDouble("currentTime", stopWatch.getTimeSeconds());
          body.putString("path", currentOutputFilePath);

          sendEvent(AudioRecorderEventProgress, body);
        }
      }
    }, 0, progressUpdateInterval);
  }

  private void stopTimer(){
    if (timer != null) {
      timer.cancel();
      timer.purge();
      timer = null;
    }
  }

  private void sendEvent(String eventName, Object params) {
    getReactApplicationContext()
        .getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter.class)
        .emit(eventName, params);
  }

  private void logAndRejectPromise(Promise promise, String errorCode, String errorMessage) {
    Log.e(TAG, errorMessage);
    promise.reject(errorCode, errorMessage);
  }

  private boolean makeDir(@Nullable File dir) {
    if (dir == null) {
      return false;
    }

    try {
      if (dir.exists()) {
        return true;
      }

      return dir.mkdirs();
    } catch (SecurityException exception) {
      Log.e(TAG, exception.getLocalizedMessage());
      return false;
    }
  }

  private void reset(boolean clean) {
    release(recorder);

    if (clean) {
      deletePath(currentOutputFilePath);
    }

    recorder = null;
    currentOutputFilePath = null;
    currentMaxDuration = 0;
    isRecording = false;
    isPaused = false;
    stopTimer();
    stopWatch.reset();
  }

  private void reset() {
    reset(true);
  }


  private void release(MediaRecorder mediaRecorder) {
    if (mediaRecorder != null) {
      mediaRecorder.setOnErrorListener(null);
      mediaRecorder.setOnInfoListener(null);
      mediaRecorder.reset();
      mediaRecorder.release();
    }
  }

  private boolean deleteRecursive(File fileOrDirectory) throws SecurityException {
    if (fileOrDirectory.isDirectory()) {
      boolean allFilesDeleted = true;

      for (File child : fileOrDirectory.listFiles()) {
        if (!deleteRecursive(child)) {
          allFilesDeleted = false;
        }
      }

      return allFilesDeleted;
    }

    return fileOrDirectory.delete();
  }

  private boolean deletePath(@Nullable String path) {
    if (path == null) {
      return true;
    }

    try {
      File file = new File(path);

      if (!file.exists()) {
        return true;
      }

      return deleteRecursive(file);
    } catch (Exception e) {
      Log.d(TAG, "Failed to delete path " + path, e);
      return false;
    }
  }
}
