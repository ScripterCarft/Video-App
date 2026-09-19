import { StyleSheet, Text, View } from 'react-native';

export function NowPlayingAccessory() {
  return (
    <View style={styles.container}>
      <Text style={styles.text} numberOfLines={1}>
        Nothing Playing
      </Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    justifyContent: 'center',
    paddingHorizontal: 12,
  },
  text: {
    fontSize: 13,
    color: '#8E8E93',
  },
});
