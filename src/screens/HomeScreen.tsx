import { FlatList, StyleSheet } from 'react-native';
import { dummyVideos } from '../data/dummyData';
import { VideoRow } from '../components/VideoRow';

export function HomeScreen() {
  return (
    <FlatList
      style={styles.list}
      contentInsetAdjustmentBehavior="automatic"
      data={dummyVideos}
      keyExtractor={(video) => video.id}
      renderItem={({ item }) => <VideoRow video={item} />}
    />
  );
}

const styles = StyleSheet.create({
  list: {
    flex: 1,
    backgroundColor: 'white',
  },
});
