import type { CapacitorConfig } from '@capacitor/cli'

const config: CapacitorConfig = {
  appId: 'com.example.app',
  appName: 'comfyui-mobile-web',
  webDir: 'dist',
  server: {
    cleartext: true,
  },
}

export default config
