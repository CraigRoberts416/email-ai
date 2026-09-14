import { useEffect, useRef, useState } from 'react';
import {
  Dimensions,
  KeyboardAvoidingView,
  Modal,
  Platform,
  Pressable,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import Animated, {
  Easing,
  FadeIn,
  runOnJS,
  useAnimatedStyle,
  useSharedValue,
  withSpring,
  withTiming,
} from 'react-native-reanimated';
import { Gesture, GestureDetector } from 'react-native-gesture-handler';
import * as Haptics from 'expo-haptics';
import { IconSymbol } from '@/components/ui/icon-symbol';
import { Motion, Radius, Spacing, Theme, Type } from '@/constants/theme';

const { height: SCREEN_H } = Dimensions.get('window');
const SHEET_H = Math.min(560, SCREEN_H * 0.85);

// ─── Types ────────────────────────────────────────────────────────────────

export type DiscussMessage = {
  id:        string;
  role:      'user' | 'ai';
  content:   string;
  streaming?: boolean;
};

export type DiscussContext = {
  messageId:   string;
  senderName:  string;
  headline:    string | null;
};

type Props = {
  visible: boolean;
  onClose: () => void;
  context: DiscussContext | null;
  // Wire this to the backend once /discuss lands; UI is offline-friendly.
  onSend?: (text: string) => Promise<void>;
  messages: DiscussMessage[];
  // Optional proactive AI opener — arrives before user types anything.
  proactive?: string | null;
};

// ─── Component ────────────────────────────────────────────────────────────

export default function DiscussSheet({ visible, onClose, context, onSend, messages, proactive }: Props) {
  const translateY = useSharedValue(SHEET_H);
  const [input, setInput] = useState('');
  const inputRef = useRef<TextInput>(null);

  useEffect(() => {
    if (visible) {
      translateY.value = withSpring(0, Motion.spring.sheet);
      Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Medium).catch(() => {});
    } else {
      translateY.value = withTiming(SHEET_H, {
        duration: Motion.timing.reveal,
        easing: Easing.out(Easing.cubic),
      });
    }
  }, [visible, translateY]);

  const dismiss = () => onClose();
  const dismissWithHaptic = () => { Haptics.selectionAsync().catch(() => {}); dismiss(); };

  const drag = Gesture.Pan()
    .onUpdate((e) => {
      translateY.value = Math.max(0, e.translationY);
    })
    .onEnd((e) => {
      const shouldDismiss = e.velocityY > 900 || translateY.value > SHEET_H * 0.5;
      if (shouldDismiss) {
        translateY.value = withTiming(SHEET_H, { duration: 220 });
        runOnJS(dismiss)();
      } else {
        translateY.value = withSpring(0, Motion.spring.sheet);
      }
    });

  const sheetStyle = useAnimatedStyle(() => ({
    transform: [{ translateY: translateY.value }],
  }));

  const backdropStyle = useAnimatedStyle(() => ({
    opacity: 1 - Math.min(1, translateY.value / SHEET_H),
  }));

  if (!visible) return null;

  const submit = async () => {
    const text = input.trim();
    if (!text) return;
    setInput('');
    Haptics.selectionAsync().catch(() => {});
    if (onSend) await onSend(text);
  };

  return (
    <Modal
      visible={visible}
      transparent
      statusBarTranslucent
      animationType="none"
      onRequestClose={dismiss}
    >
      <View style={StyleSheet.absoluteFill} pointerEvents="box-none">
      {/* Scrim */}
      <Animated.View
        style={[styles.backdrop, backdropStyle]}
        pointerEvents={visible ? 'auto' : 'none'}
      >
        <Pressable style={StyleSheet.absoluteFill} onPress={dismissWithHaptic} />
      </Animated.View>

      {/* Sheet */}
      <Animated.View style={[styles.sheet, sheetStyle]}>
        <GestureDetector gesture={drag}>
          <View style={styles.grabber} />
        </GestureDetector>

        <View style={styles.header}>
          <View style={{ flex: 1 }}>
            <Text style={styles.title}>Discuss</Text>
            {context && (
              <Text style={styles.subtitle} numberOfLines={1}>
                {context.senderName}{context.headline ? ` · ${context.headline}` : ''}
              </Text>
            )}
          </View>
          <Pressable
            onPress={dismissWithHaptic}
            hitSlop={12}
            accessibilityRole="button"
            accessibilityLabel="Close"
            style={styles.closeBtn}
          >
            <IconSymbol name="xmark" size={18} color={Theme.textSecondary} />
          </Pressable>
        </View>

        <KeyboardAvoidingView
          style={styles.body}
          behavior={Platform.OS === 'ios' ? 'padding' : undefined}
          keyboardVerticalOffset={0}
        >
          <View style={styles.thread}>
            {proactive && (
              <Animated.View entering={FadeIn.duration(240)} style={[styles.bubble, styles.bubbleAi]}>
                <Text style={styles.bubbleMeta}>Reading now</Text>
                <Text style={styles.bubbleText}>{proactive}</Text>
              </Animated.View>
            )}
            {messages.map(m => (
              <View
                key={m.id}
                style={[
                  styles.bubble,
                  m.role === 'ai' ? styles.bubbleAi : styles.bubbleUser,
                ]}
              >
                <Text style={m.role === 'ai' ? styles.bubbleText : styles.bubbleTextUser}>
                  {m.content}
                  {m.streaming ? '▍' : ''}
                </Text>
              </View>
            ))}
          </View>

          <View style={styles.composer}>
            <TextInput
              ref={inputRef}
              value={input}
              onChangeText={setInput}
              placeholder="Ask about this email…"
              placeholderTextColor={Theme.textTertiary}
              style={styles.input}
              multiline
              onSubmitEditing={submit}
              returnKeyType="send"
            />
            <Pressable
              onPress={submit}
              disabled={!input.trim()}
              accessibilityRole="button"
              accessibilityLabel="Send"
              style={[styles.sendBtn, !input.trim() && styles.sendBtnDisabled]}
            >
              <IconSymbol
                name="arrow.up"
                size={18}
                color={input.trim() ? Theme.bg : Theme.textTertiary}
              />
            </Pressable>
          </View>
        </KeyboardAvoidingView>
      </Animated.View>
      </View>
    </Modal>
  );
}

// ─── Styles ───────────────────────────────────────────────────────────────

const styles = StyleSheet.create({
  backdrop: {
    ...StyleSheet.absoluteFillObject,
    backgroundColor: Theme.scrim,
  },
  sheet: {
    position: 'absolute',
    left: 0, right: 0, bottom: 0,
    height: SHEET_H,
    backgroundColor: Theme.elevated,
    borderTopLeftRadius: Radius.sheet,
    borderTopRightRadius: Radius.sheet,
    overflow: 'hidden',
  },
  grabber: {
    width: 40,
    height: 4,
    borderRadius: 2,
    backgroundColor: Theme.border,
    alignSelf: 'center',
    marginTop: Spacing.sm,
    marginBottom: Spacing.md,
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: Spacing.lg,
    paddingBottom: Spacing.md,
    gap: Spacing.md,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: Theme.border,
  },
  title: {
    ...Type.headline,
    color: Theme.textPrimary,
  },
  subtitle: {
    ...Type.caption,
    color: Theme.textSecondary,
    marginTop: 2,
  },
  closeBtn: {
    width: 36, height: 36,
    borderRadius: Radius.round,
    backgroundColor: Theme.surface,
    alignItems: 'center',
    justifyContent: 'center',
  },
  body: {
    flex: 1,
  },
  thread: {
    flex: 1,
    padding: Spacing.lg,
    gap: Spacing.md,
  },
  bubble: {
    padding: Spacing.md,
    borderRadius: Radius.media,
    maxWidth: '92%',
  },
  bubbleAi: {
    backgroundColor: Theme.surface,
    alignSelf: 'flex-start',
  },
  bubbleUser: {
    backgroundColor: Theme.accent,
    alignSelf: 'flex-end',
  },
  bubbleMeta: {
    ...Type.chip,
    color: Theme.textTertiary,
    marginBottom: Spacing.xs,
  },
  bubbleText: {
    ...Type.body,
    color: Theme.textPrimary,
  },
  bubbleTextUser: {
    ...Type.body,
    color: Theme.bg,
  },
  composer: {
    flexDirection: 'row',
    alignItems: 'flex-end',
    gap: Spacing.sm,
    padding: Spacing.md,
    borderTopWidth: StyleSheet.hairlineWidth,
    borderTopColor: Theme.border,
    backgroundColor: Theme.elevated,
  },
  input: {
    flex: 1,
    minHeight: 40,
    maxHeight: 120,
    backgroundColor: Theme.surface,
    borderRadius: Radius.control,
    paddingHorizontal: Spacing.md,
    paddingVertical: Spacing.sm,
    color: Theme.textPrimary,
    ...Type.body,
  },
  sendBtn: {
    width: 40, height: 40,
    borderRadius: Radius.round,
    backgroundColor: Theme.accent,
    alignItems: 'center',
    justifyContent: 'center',
  },
  sendBtnDisabled: {
    backgroundColor: Theme.surface,
  },
});
