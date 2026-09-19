import { createNativeStackNavigator } from '@react-navigation/native-stack';
import { HomeScreen } from '../screens/HomeScreen';
import { ProfileButton } from '../components/ProfileButton';

const Stack = createNativeStackNavigator();

export function HomeStack() {
  return (
    <Stack.Navigator screenOptions={{ headerRight: () => <ProfileButton /> }}>
      <Stack.Screen name="Home" component={HomeScreen} options={{ headerLargeTitle: true }} />
    </Stack.Navigator>
  );
}
