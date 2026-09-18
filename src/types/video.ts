export interface Channel {
  id: string;
  name: string;
  avatarColor: string;
  subscriberCount: string;
}

export interface Video {
  id: string;
  title: string;
  channel: Channel;
  durationLabel: string;
  viewsLabel: string;
  publishedLabel: string;
  thumbnailColor: string;
  commentsEnabled: boolean;
}
