import { PlatformColor, StyleSheet, Text, View } from 'react-native';
import { Video } from '../types/video';
import { useStrings } from '../i18n/strings';

interface VideoRowProps {
  video: Video;
}

export function VideoRow({ video }: VideoRowProps) {
  const strings = useStrings();

  return (
    <View style={styles.row}>
      <View style={[styles.thumbnail, { backgroundColor: video.thumbnailColor }]}>
        <Text style={styles.duration}>{video.durationLabel}</Text>
      </View>
      <View style={styles.textBlock}>
        <Text style={styles.title} numberOfLines={2}>
          {video.title}
        </Text>
        <Text style={styles.meta} numberOfLines={1}>
          {video.channel.name}
        </Text>
        <Text style={styles.meta} numberOfLines={1}>
          {strings.video.views(video.viewsLabel)} · {video.publishedLabel}
        </Text>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  row: {
    flexDirection: 'row',
    paddingVertical: 10,
    paddingHorizontal: 16,
    gap: 12,
  },
  thumbnail: {
    width: 140,
    height: 79,
    borderRadius: 10,
    justifyContent: 'flex-end',
    alignItems: 'flex-end',
    overflow: 'hidden',
  },
  duration: {
    color: 'white',
    fontSize: 11,
    fontWeight: '600',
    backgroundColor: 'rgba(0,0,0,0.6)',
    paddingHorizontal: 4,
    paddingVertical: 1,
    borderRadius: 4,
    margin: 4,
  },
  textBlock: {
    flex: 1,
    justifyContent: 'center',
  },
  title: {
    color: PlatformColor('label'),
    fontSize: 15,
    fontWeight: '600',
    marginBottom: 4,
  },
  meta: {
    fontSize: 13,
    color: PlatformColor('secondaryLabel'),
  },
});
