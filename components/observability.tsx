import {
  BatchSize,
  DatadogProvider,
  DatadogProviderConfiguration,
  DdRum,
  RumActionType,
  SdkVerbosity,
  TrackingConsent,
  UploadFrequency,
} from '@datadog/mobile-react-native';
import {
  ImagePrivacyLevel,
  SessionReplay,
  TextAndInputPrivacyLevel,
  TouchPrivacyLevel,
} from '@datadog/mobile-react-native-session-replay';
import { PropsWithChildren, useEffect } from 'react';

const config = new DatadogProviderConfiguration(
  'pub83419a0f322102997f55f5342d1a8635',
  'prod',
  TrackingConsent.GRANTED,
  {
    rumConfiguration: {
      applicationId: 'dcea72ee-32a7-4eff-97b6-72501fdbdf9c',
      trackInteractions: true,
      trackResources: true,
      trackErrors: true,
      nativeCrashReportEnabled: true,
      sessionSampleRate: 100,
      longTaskThresholdMs: 100,
    },
    logsConfiguration: {},
    traceConfiguration: {},
  }
);
config.site = 'US5';

if (__DEV__) {
  config.uploadFrequency = UploadFrequency.FREQUENT;
  config.batchSize = BatchSize.SMALL;
  config.verbosity = SdkVerbosity.DEBUG;
}

// Enables Session Replay once the SDK is ready. Must render inside the provider.
// Privacy: touches visible, sensitive inputs masked, images visible.
function SessionReplayConfigure() {
  useEffect(() => {
    SessionReplay.enable({
      replaySampleRate: 100,
      touchPrivacyLevel: TouchPrivacyLevel.SHOW,
      textAndInputPrivacyLevel: TextAndInputPrivacyLevel.MASK_SENSITIVE_INPUTS,
      imagePrivacyLevel: ImagePrivacyLevel.MASK_NONE,
    }).catch(e => console.warn('[datadog] session replay init failed:', e));
  }, []);
  return null;
}

export function Observability({ children }: PropsWithChildren) {
  return (
    <DatadogProvider configuration={config}>
      <SessionReplayConfigure />
      {children}
    </DatadogProvider>
  );
}

// ─── Telemetry surface ───────────────────────────────────────────────────
// Every DdRum call in the app routes through here so the web build (which
// has no native module) can no-op instead of crashing.

export function trackAction(name: string, attrs?: Record<string, unknown>) {
  DdRum.addAction(RumActionType.TAP, name, attrs ?? {}).catch(() => {});
}

export function trackViewAttribute(key: string, value: unknown) {
  DdRum.addViewAttribute(key, value).catch(() => {});
}

export function startView(key: string, name: string) {
  DdRum.startView(key, name).catch(() => {});
}

export function stopView(key: string) {
  DdRum.stopView(key).catch(() => {});
}
