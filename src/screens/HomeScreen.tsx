import { FlatList, StyleSheet, Text, View } from 'react-native';
import { SymbolView } from 'expo-symbols';
import { dummyVideos } from '../data/dummyData';
import { VideoRow } from '../components/VideoRow';

// TEMP: house icon picker, remove once a final icon is chosen.
const HOUSE_ICON_CANDIDATES = [
  'house',
  'house.fill',
  'house.circle',
  'house.circle.fill',
  'house.and.flag',
  'house.and.flag.fill',
  'house.lodge',
  'house.lodge.fill',
  'building',
  'building.fill',
  'building.columns',
  'building.columns.fill',
];

function HouseIconPicker() {
  return (
    <View style={styles.pickerGrid}>
      {HOUSE_ICON_CANDIDATES.map((name) => (
        <View key={name} style={styles.pickerCell}>
          <SymbolView
            name={name as never}
            size={36}
            tintColor="#000"
            fallback={<Text style={styles.pickerMissing}>?</Text>}
          />
          <Text style={styles.pickerLabel}>{name}</Text>
        </View>
      ))}
    </View>
  );
}

export function HomeScreen() {
  return (
    <FlatList
      style={styles.list}
      contentInsetAdjustmentBehavior="automatic"
      data={dummyVideos}
      keyExtractor={(video) => video.id}
      ListHeaderComponent={<HouseIconPicker />}
      renderItem={({ item }) => <VideoRow video={item} />}
    />
  );
}

const styles = StyleSheet.create({
  list: {
    flex: 1,
    backgroundColor: 'white',
  },
  pickerGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    paddingHorizontal: 12,
    paddingTop: 8,
    paddingBottom: 4,
    gap: 4,
  },
  pickerCell: {
    width: 90,
    alignItems: 'center',
    paddingVertical: 8,
  },
  pickerLabel: {
    fontSize: 10,
    color: '#8E8E93',
    marginTop: 4,
    textAlign: 'center',
  },
  pickerMissing: {
    fontSize: 24,
    color: '#C7C7CC',
  },
});
