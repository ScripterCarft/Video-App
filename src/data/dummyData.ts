import { Channel, Video } from '../types/video';

const channels: Channel[] = [
  { id: 'c1', name: 'Kurzgesagt', avatarColor: '#FF6B6B', subscriberCount: '22 Mio.' },
  { id: 'c2', name: 'Marques Brownlee', avatarColor: '#4D96FF', subscriberCount: '19 Mio.' },
  { id: 'c3', name: 'Veritasium', avatarColor: '#6BCB77', subscriberCount: '15 Mio.' },
  { id: 'c4', name: 'Coding Garden', avatarColor: '#FFD93D', subscriberCount: '210 Tsd.' },
  { id: 'c5', name: 'Two Minute Papers', avatarColor: '#C77DFF', subscriberCount: '1,6 Mio.' },
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
    title: 'Warum die Zeit manchmal schneller vergeht',
    channel: channelById('c1'),
    durationLabel: '8:42',
    viewsLabel: '1,2 Mio. Aufrufe',
    publishedLabel: 'vor 3 Tagen',
    thumbnailColor: '#FF6B6B',
    commentsEnabled: true,
  },
  {
    id: 'v2',
    title: 'Das neue iPhone im Alltagstest – lohnt sich das Upgrade?',
    channel: channelById('c2'),
    durationLabel: '14:05',
    viewsLabel: '890 Tsd. Aufrufe',
    publishedLabel: 'vor 1 Tag',
    thumbnailColor: '#4D96FF',
    commentsEnabled: true,
  },
  {
    id: 'v3',
    title: 'Das seltsamste Experiment der Physik',
    channel: channelById('c3'),
    durationLabel: '21:17',
    viewsLabel: '3,4 Mio. Aufrufe',
    publishedLabel: 'vor 2 Wochen',
    thumbnailColor: '#6BCB77',
    commentsEnabled: false,
  },
  {
    id: 'v4',
    title: 'React Native Navigation in 10 Minuten erklärt',
    channel: channelById('c4'),
    durationLabel: '10:02',
    viewsLabel: '54 Tsd. Aufrufe',
    publishedLabel: 'vor 5 Tagen',
    thumbnailColor: '#FFD93D',
    commentsEnabled: true,
  },
  {
    id: 'v5',
    title: 'Diese KI kann jetzt komplette Spiele bauen',
    channel: channelById('c5'),
    durationLabel: '6:33',
    viewsLabel: '620 Tsd. Aufrufe',
    publishedLabel: 'vor 6 Stunden',
    thumbnailColor: '#C77DFF',
    commentsEnabled: true,
  },
  {
    id: 'v6',
    title: 'Wie Schwarze Löcher wirklich funktionieren',
    channel: channelById('c1'),
    durationLabel: '12:50',
    viewsLabel: '2,1 Mio. Aufrufe',
    publishedLabel: 'vor 1 Monat',
    thumbnailColor: '#FF6B6B',
    commentsEnabled: true,
  },
];

export const dummyChannels = channels;

export const subscribedChannelIds = ['c1', 'c2', 'c3'];

export function videosForChannel(channelId: string): Video[] {
  return dummyVideos.filter((video) => video.channel.id === channelId);
}
