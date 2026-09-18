import { NavigationContainer } from '@react-navigation/native';
import { StatusBar } from 'expo-status-bar';
import { RootTabs } from './src/navigation/RootTabs';

export default function App() {
  return (
    <NavigationContainer>
      <RootTabs />
      <StatusBar style="auto" />
    </NavigationContainer>
  );
}
