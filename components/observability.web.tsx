import { PropsWithChildren } from 'react';

// Datadog's RN SDK (and especially session-replay) imports react-native
// internals Metro refuses to bundle for web, and its native module is absent
// there anyway. Web is a dev/preview surface, so observability no-ops.

export function Observability({ children }: PropsWithChildren) {
  return <>{children}</>;
}

export function trackAction(_name: string, _attrs?: Record<string, unknown>) {}
export function trackViewAttribute(_key: string, _value: unknown) {}
export function startView(_key: string, _name: string) {}
export function stopView(_key: string) {}
