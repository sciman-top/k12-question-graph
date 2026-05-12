import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

const localApiProxy = {
  target: 'http://127.0.0.1:5275',
  changeOrigin: true,
}

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],
  server: {
    proxy: {
      '/health': localApiProxy,
      '/imports': localApiProxy,
      '/source-documents': localApiProxy,
      '/questions': localApiProxy,
      '/review-queue': localApiProxy,
      '/review-workbench': localApiProxy,
      '/paper-blueprints': localApiProxy,
      '/assessments': localApiProxy,
    },
  },
  build: {
    rollupOptions: {
      output: {
        manualChunks(id) {
          if (id.includes('node_modules/react') || id.includes('node_modules/react-dom')) {
            return 'react-vendor'
          }

          if (id.includes('node_modules/@ant-design/icons')) {
            return 'antd-icons-vendor'
          }

          if (id.includes('node_modules/@ant-design')) {
            return 'antd-core-vendor'
          }

          if (id.includes('node_modules/antd')) {
            return 'antd-vendor'
          }

          if (id.includes('node_modules/rc-')) {
            return 'antd-rc-vendor'
          }

          if (id.includes('node_modules/@tanstack')) {
            return 'query-vendor'
          }

          if (id.includes('node_modules')) {
            return 'vendor'
          }

          return undefined
        },
      },
    },
  },
})
