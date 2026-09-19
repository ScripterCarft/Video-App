import { FlatList, StyleSheet, Text, View } from 'react-native';
import { dummyChannels, subscribedChannelIds, videosForChannel } from '../data/dummyData';
import { useStrings } from '../i18n/strings';

const subscribedChannels = dummyChannels.filter((channel) =>
  subscribedChannelIds.includes(channel.id)
);

export function SubscriptionsScreen() {
  const strings = useStrings();

  return (
    <FlatList
      style={styles.list}
      contentInsetAdjustmentBehavior="automatic"
      data={subscribedChannels}
      keyExtractor={(channel) => channel.id}
      renderItem={({ item }) => (
        <View style={styles.row}>
          <View style={[styles.avatar, { backgroundColor: item.avatarColor }]} />
          <View style={styles.textBlock}>
            <Text style={styles.name}>{item.name}</Text>
            <Text style={styles.meta}>
              {strings.channel.subscribers(
                item.subscriberCount,
                videosForChannel(item.id).length
              )}
            </Text>
          </View>
        </View>
      )}
    />
  );
}

const styles = StyleSheet.create({
  list: {
    flex: 1,
    backgroundColor: 'white',
  },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 12,
    paddingHorizontal: 16,
    gap: 12,
  },
  avatar: {
    width: 48,
    height: 48,
    borderRadius: 24,
  },
  textBlock: {
    flex: 1,
  },
  name: {
    fontSize: 15,
    fontWeight: '600',
    marginBottom: 2,
  },
  meta: {
    fontSize: 13,
    color: '#8E8E93',
  },
});
