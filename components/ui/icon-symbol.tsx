// Fallback for using MaterialIcons on Android and web.

import MaterialIcons from '@expo/vector-icons/MaterialIcons';
import { SymbolWeight, SymbolViewProps } from 'expo-symbols';
import { ComponentProps } from 'react';
import { OpaqueColorValue, type StyleProp, type TextStyle } from 'react-native';

type IconMapping = Record<SymbolViewProps['name'], ComponentProps<typeof MaterialIcons>['name']>;
type IconSymbolName = keyof typeof MAPPING;

/**
 * Add your SF Symbols to Material Icons mappings here.
 * - see Material Icons in the [Icons Directory](https://icons.expo.fyi).
 * - see SF Symbols in the [SF Symbols](https://developer.apple.com/sf-symbols/) app.
 */
const MAPPING = {
  // ── tabs / nav ──
  'house.fill':      'home',
  'house':           'home',
  'paperplane.fill': 'send',
  'paperplane':      'send',
  'chevron.left.forwardslash.chevron.right': 'code',
  'chevron.left':    'chevron-left',
  'chevron.right':   'chevron-right',
  'chevron.down':    'expand-more',
  'chevron.up':      'expand-less',
  // ── feed card ──
  'ellipsis':                    'more-horiz',
  'xmark':                       'close',
  'checkmark':                   'check',
  'sparkles':                    'auto-awesome',
  'bookmark':                    'bookmark-border',
  'bookmark.fill':               'bookmark',
  'trash':                       'delete-outline',
  'archivebox':                  'archive',
  'archivebox.fill':             'archive',
  'arrowshape.turn.up.left':     'reply',
  'arrowshape.turn.up.right':    'forward',
  'arrow.turn.up.left':          'reply',
  'arrow.turn.up.right':         'forward',
  'arrow.clockwise':             'refresh',
  'arrow.up':                    'arrow-upward',
  'arrow.up.circle':             'arrow-upward',
  'face.smiling':                'sentiment-satisfied-alt',
  'magnifyingglass':             'search',
  'gearshape':                   'settings',
  'envelope':                    'mail-outline',
  'envelope.fill':               'mail',
  'exclamationmark.triangle':    'warning',
  'exclamationmark.circle':      'error-outline',
  'lock':                        'lock',
  'bell':                        'notifications-none',
  'plus':                        'add',
  'minus':                       'remove',
  'flag':                        'flag',
  'eye.slash':                   'visibility-off',
  'person.crop.circle':          'account-circle',
  'clock':                       'schedule',
  'bubble.left.and.bubble.right':'forum',
} as IconMapping;

/**
 * An icon component that uses native SF Symbols on iOS, and Material Icons on Android and web.
 * This ensures a consistent look across platforms, and optimal resource usage.
 * Icon `name`s are based on SF Symbols and require manual mapping to Material Icons.
 */
export function IconSymbol({
  name,
  size = 24,
  color,
  style,
}: {
  name: IconSymbolName;
  size?: number;
  color: string | OpaqueColorValue;
  style?: StyleProp<TextStyle>;
  weight?: SymbolWeight;
}) {
  return <MaterialIcons color={color} size={size} name={MAPPING[name]} style={style} />;
}
