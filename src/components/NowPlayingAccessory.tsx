import { StyleSheet, Text, View } from 'react-native';

export function NowPlayingAccessory() {
  return (
    <View style={styles.container}>
      <View style={styles.thumbnail} />
      <Text style={styles.title} numberOfLines={1}>
        Nothing Playing
      </Text>
      <View style={styles.playButton}>
        <View style={styles.playTriangle} />
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 10,
    gap: 10,
  },
  thumbnail: {
    width: 30,
    height: 30,
    borderRadius: 6,
    backgroundColor: '#E5E5EA',
  },
  title: {
    flex: 1,
    fontSize: 14,
    fontWeight: '500',
    color: '#C7C7CC',
  },
  playButton: {
    width: 30,
    height: 30,
    alignItems: 'center',
    justifyContent: 'center',
  },
  playTriangle: {
    width: 0,
    height: 0,
    marginLeft: 3,
    borderTopWidth: 7,
    borderBottomWidth: 7,
    borderLeftWidth: 11,
    borderTopColor: 'transparent',
    borderBottomColor: 'transparent',
    borderLeftColor: '#C7C7CC',
  },
});
