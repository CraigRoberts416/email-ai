import { Modal, Pressable, StyleSheet, Text } from 'react-native';
import Animated, { FadeIn, FadeOut, SlideInDown, SlideOutDown } from 'react-native-reanimated';
import * as Haptics from 'expo-haptics';
import { IconSymbol } from '@/components/ui/icon-symbol';
import { Radius, Spacing, Theme, Type } from '@/constants/theme';

export type OverflowItem = {
  key:      string;
  label:    string;
  icon:     any;
  destructive?: boolean;
  onPress:  () => void;
};

type Props = {
  visible: boolean;
  onClose: () => void;
  items:   OverflowItem[];
  title?:  string;
};

export default function OverflowMenu({ visible, onClose, items, title }: Props) {
  return (
    <Modal
      visible={visible}
      transparent
      statusBarTranslucent
      animationType="none"
      onRequestClose={onClose}
    >
      {visible && (
        <>
          <Animated.View
            entering={FadeIn.duration(180)}
            exiting={FadeOut.duration(160)}
            style={styles.backdrop}
          >
            <Pressable style={StyleSheet.absoluteFill} onPress={onClose} />
          </Animated.View>

          <Animated.View
            entering={SlideInDown.duration(220)}
            exiting={SlideOutDown.duration(200)}
            style={styles.sheet}
          >
            {title && <Text style={styles.title}>{title}</Text>}
            {items.map((item, idx) => (
              <Pressable
                key={item.key}
                onPress={() => {
                  Haptics.selectionAsync().catch(() => {});
                  onClose();
                  // Give the modal a beat to dismiss before the action fires.
                  setTimeout(item.onPress, 60);
                }}
                style={({ pressed }) => [
                  styles.row,
                  idx === 0 && !title && { borderTopWidth: 0 },
                  pressed && styles.rowPressed,
                ]}
                accessibilityRole="button"
                accessibilityLabel={item.label}
              >
                <IconSymbol
                  name={item.icon}
                  size={20}
                  color={item.destructive ? Theme.danger : Theme.textPrimary}
                />
                <Text style={[
                  styles.label,
                  item.destructive && { color: Theme.danger },
                ]}>
                  {item.label}
                </Text>
              </Pressable>
            ))}

            <Pressable
              onPress={onClose}
              style={({ pressed }) => [styles.cancel, pressed && styles.rowPressed]}
              accessibilityRole="button"
            >
              <Text style={styles.cancelLabel}>Cancel</Text>
            </Pressable>
          </Animated.View>
        </>
      )}
    </Modal>
  );
}

const styles = StyleSheet.create({
  backdrop: {
    ...StyleSheet.absoluteFillObject,
    backgroundColor: Theme.scrim,
  },
  sheet: {
    position: 'absolute',
    left: Spacing.md, right: Spacing.md, bottom: Spacing.xl,
    backgroundColor: Theme.elevated,
    borderRadius: Radius.sheet,
    overflow: 'hidden',
    paddingBottom: Spacing.sm,
  },
  title: {
    ...Type.chip,
    color: Theme.textTertiary,
    paddingHorizontal: Spacing.lg,
    paddingTop: Spacing.md,
    paddingBottom: Spacing.sm,
  },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.md,
    paddingHorizontal: Spacing.lg,
    paddingVertical: Spacing.md,
    borderTopWidth: StyleSheet.hairlineWidth,
    borderTopColor: Theme.border,
  },
  rowPressed: {
    backgroundColor: Theme.surface,
  },
  label: {
    ...Type.body,
    color: Theme.textPrimary,
  },
  cancel: {
    marginTop: Spacing.xs,
    marginHorizontal: Spacing.md,
    paddingVertical: Spacing.md,
    borderRadius: Radius.control,
    backgroundColor: Theme.surface,
    alignItems: 'center',
  },
  cancelLabel: {
    ...Type.sender,
    color: Theme.textPrimary,
  },
});
