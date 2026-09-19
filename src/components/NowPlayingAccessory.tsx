import { Pressable, StyleSheet, View } from 'react-native';
import { SymbolView } from 'expo-symbols';

type Placement = 'regular' | 'inline';

interface NowPlayingAccessoryProps {
  placement?: Placement;
}

export function NowPlayingAccessory({
  placement = 'regular',
}: NowPlayingAccessoryProps) {
  return (
    <View style={styles.container}>
      <View style={styles.thumbnail} />
      <View style={styles.textStack}>
        <View style={styles.titlePlaceholder} />
        <View style={styles.subtitlePlaceholder} />
      </View>
      <View style={styles.controls}>
        {placement === 'regular' && (
          <Pressable hitSlop={8} style={styles.controlButton}>
            <SymbolView name="goforward.30" size={22} tintColor="#C7C7CC" />
          </Pressable>
        )}
        <Pressable hitSlop={8} style={styles.controlButton}>
          <SymbolView name="play.fill" size={20} tintColor="#C7C7CC" />
        </Pressable>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 16,
    gap: 12,
  },
  thumbnail: {
    width: 32,
    height: 32,
    borderRadius: 6,
    backgroundColor: '#E5E5EA',
  },
  textStack: {
    flex: 1,
    gap: 6,
  },
  titlePlaceholder: {
    width: '55%',
    height: 10,
    borderRadius: 3,
    backgroundColor: '#E5E5EA',
  },
  subtitlePlaceholder: {
    width: '35%',
    height: 8,
    borderRadius: 3,
    backgroundColor: '#F0F0F2',
  },
  controls: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
  },
  controlButton: {
    width: 44,
    height: 44,
    alignItems: 'center',
    justifyContent: 'center',
  },
});
