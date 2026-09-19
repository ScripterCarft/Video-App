import { Channel, Video } from '../types/video';

const channels: Channel[] = [
  { id: 'c1', name: 'Kurzgesagt', avatarColor: '#FF6B6B', subscriberCount: '22M' },
  { id: 'c2', name: 'Marques Brownlee', avatarColor: '#4D96FF', subscriberCount: '19M' },
  { id: 'c3', name: 'Veritasium', avatarColor: '#6BCB77', subscriberCount: '15M' },
  { id: 'c4', name: 'Coding Garden', avatarColor: '#FFD93D', subscriberCount: '210K' },
  { id: 'c5', name: 'Two Minute Papers', avatarColor: '#C77DFF', subscriberCount: '1.6M' },
];

function channelById(id: string): Channel {
  const channel = channels.find((c) => c.id === id);
  if (!channel) {
    throw new Error(`Unknown channel id: ${id}`);
  }
  return channel;
}

export const dummyVideos: Video[] = [
  {
    id: 'v1',
    title: 'Why Time Sometimes Feels Like It Speeds Up',
    channel: channelById('c1'),
    durationLabel: '8:42',
    viewsLabel: '1.2M',
    publishedLabel: '3 days ago',
    thumbnailColor: '#FF6B6B',
    commentsEnabled: true,
  },
  {
    id: 'v2',
    title: 'The New iPhone in Daily Use — Is the Upgrade Worth It?',
    channel: channelById('c2'),
    durationLabel: '14:05',
    viewsLabel: '890K',
    publishedLabel: '1 day ago',
    thumbnailColor: '#4D96FF',
    commentsEnabled: true,
  },
  {
    id: 'v3',
    title: "Physics' Strangest Experiment",
    channel: channelById('c3'),
    durationLabel: '21:17',
    viewsLabel: '3.4M',
    publishedLabel: '2 weeks ago',
    thumbnailColor: '#6BCB77',
    commentsEnabled: false,
  },
  {
    id: 'v4',
    title: 'React Native Navigation Explained in 10 Minutes',
    channel: channelById('c4'),
    durationLabel: '10:02',
    viewsLabel: '54K',
    publishedLabel: '5 days ago',
    thumbnailColor: '#FFD93D',
    commentsEnabled: true,
  },
  {
    id: 'v5',
    title: 'This AI Can Now Build Entire Games',
    channel: channelById('c5'),
    durationLabel: '6:33',
    viewsLabel: '620K',
    publishedLabel: '6 hours ago',
    thumbnailColor: '#C77DFF',
    commentsEnabled: true,
  },
  {
    id: 'v6',
    title: 'How Black Holes Actually Work',
    channel: channelById('c1'),
    durationLabel: '12:50',
    viewsLabel: '2.1M',
    publishedLabel: '1 month ago',
    thumbnailColor: '#FF6B6B',
    commentsEnabled: true,
  },
];

export const dummyChannels = channels;

export const subscribedChannelIds = ['c1', 'c2', 'c3'];

export function videosForChannel(channelId: string): Video[] {
  return dummyVideos.filter((video) => video.channel.id === channelId);
}
