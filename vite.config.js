import { fileURLToPath, URL } from 'node:url'
import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

export default defineConfig({
  plugins: [vue()],
  resolve: {
    alias: {
      '@': fileURLToPath(new URL('./src', import.meta.url)),
    },
  },
  server: {
    proxy: {
      '/api': {
        target: 'http://127.0.0.1:8190',
        changeOrigin: true,
        ws: true,
        rewrite: (path) => path.replace(/^\/api/, ''),
        configure: (proxy) => {
          // 拦截并重写普通 HTTP 请求
          proxy.on('proxyReq', (proxyReq) => {
            proxyReq.setHeader('Origin', 'http://127.0.0.1:8190')
          })
          // 【必须新增这段】拦截并重写 WebSocket 握手请求！
          proxy.on('proxyReqWs', (proxyReqWs) => {
            proxyReqWs.setHeader('Origin', 'http://127.0.0.1:8190')
          })
        },
      },
    },
  },
})
