import { NavigationContainer } from '@react-navigation/native';
import { createNativeBottomTabNavigator } from '@react-navigation/bottom-tabs/unstable';
import HomeScreen from './src/screens/HomeScreen.tsx';
import FollowingScreen from './src/screens/FollowingScreen.tsx';
import LibraryScreen from './src/screens/LibraryScreen.tsx';
import SearchScreen from './src/screens/SearchScreen.tsx';
import { homeIcon, followingIcon, libraryIcon, searchIcon } from './src/navigation/TabIcons';

const Tab = createNativeBottomTabNavigator();

function App() {
  return (
    <NavigationContainer>
      <Tab.Navigator>
        <Tab.Screen
          name="Home"
          component={HomeScreen}
          options={{ tabBarIcon: homeIcon }}
        />
        <Tab.Screen
          name="Following"
          component={FollowingScreen}
          options={{ tabBarIcon: followingIcon }}
        />
        <Tab.Screen
          name="Library"
          component={LibraryScreen}
          options={{ tabBarIcon: libraryIcon }}
        />
        <Tab.Screen
          name="Search"
          component={SearchScreen}
          options={{ tabBarIcon: searchIcon }}
        />
      </Tab.Navigator>
    </NavigationContainer>
  );
}

export default App;
