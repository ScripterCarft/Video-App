import { createBottomTabNavigator } from '@react-navigation/bottom-tabs';
import { HomeStack } from './HomeStack';
import { SearchStack } from './SearchStack';
import { SubscriptionsStack } from './SubscriptionsStack';
import { LibraryStack } from './LibraryStack';
import { useStrings } from '../i18n/strings';
import { NowPlayingAccessory } from '../components/NowPlayingAccessory';

export type RootTabParamList = {
  HomeTab: undefined;
  SubscriptionsTab: undefined;
  LibraryTab: undefined;
  SearchTab: undefined;
};

const Tab = createBottomTabNavigator<RootTabParamList>();

export function RootTabs() {
  const strings = useStrings();

  return (
    <Tab.Navigator
      implementation="native"
      screenOptions={{
        tabBarMinimizeBehavior: 'onScrollDown',
        bottomAccessory: ({ placement }) => (
          <NowPlayingAccessory placement={placement} />
        ),
      }}
    >
      <Tab.Screen
        name="HomeTab"
        component={HomeStack}
        options={{
          title: strings.tabs.home,
          tabBarIcon: () => ({
            type: 'sfSymbol',
            name: 'house.fill',
          }),
        }}
      />
      <Tab.Screen
        name="SubscriptionsTab"
        component={SubscriptionsStack}
        options={{
          title: strings.tabs.subscriptions,
          tabBarIcon: ({ focused }) => ({
            type: 'sfSymbol',
            name: focused ? 'person.2.fill' : 'person.2',
          }),
        }}
      />
      <Tab.Screen
        name="LibraryTab"
        component={LibraryStack}
        options={{
          title: strings.tabs.library,
          tabBarIcon: ({ focused }) => ({
            type: 'sfSymbol',
            name: focused ? 'rectangle.stack.fill' : 'rectangle.stack',
          }),
        }}
      />
      <Tab.Screen
        name="SearchTab"
        component={SearchStack}
        options={{
          title: strings.tabs.search,
          tabBarSystemItem: 'search',
        }}
      />
    </Tab.Navigator>
  );
}
