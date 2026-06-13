import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

const localApiProxy = {
  target: 'http://127.0.0.1:5275',
  changeOrigin: true,
}

const antdAdminComponentMarkers = [
  '/antd/es/form',
  '/antd/es/input-number',
  '/antd/es/modal',
  '/antd/es/switch',
  '/antd/es/message',
]

const antdFoundationMarkers = [
  '/antd/es/badge',
  '/antd/es/config-provider',
  '/antd/es/divider',
  '/antd/es/layout',
  '/antd/es/progress',
  '/antd/es/space',
  '/antd/es/tag',
  '/antd/es/typography',
]

const antdFeedbackMarkers = [
  '/antd/es/alert',
]

const antdInputMarkers = [
  '/antd/es/button',
  '/antd/es/input',
]

const adminRcMarkers = [
  'node_modules/@rc-component/dialog',
  'node_modules/@rc-component/portal',
  'node_modules/rc-field-form',
  'node_modules/rc-input-number',
  'node_modules/rc-switch',
]

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],
  server: {
    proxy: {
      '/api/admin': localApiProxy,
      '/health': localApiProxy,
      '/imports': localApiProxy,
      '/source-documents': localApiProxy,
      '/source-regions': localApiProxy,
      '/questions': localApiProxy,
      '/review-queue': localApiProxy,
      '/review-workbench': localApiProxy,
      '/paper-blueprints': localApiProxy,
      '/assessments': localApiProxy,
      '/score-imports': localApiProxy,
    },
  },
  build: {
    rollupOptions: {
      output: {
        manualChunks(id) {
          if (antdAdminComponentMarkers.some((marker) => id.includes(marker))) {
            return 'antd-vendor-admin'
          }

          if (adminRcMarkers.some((marker) => id.includes(marker))) {
            return 'antd-admin-rc-vendor'
          }

          if (antdFoundationMarkers.some((marker) => id.includes(marker))) {
            return 'antd-vendor-foundation'
          }

          if (antdFeedbackMarkers.some((marker) => id.includes(marker))) {
            return 'antd-vendor-feedback'
          }

          if (antdInputMarkers.some((marker) => id.includes(marker))) {
            return 'antd-vendor-input'
          }

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

          if (id.includes('node_modules/rc-') || id.includes('node_modules/@rc-component/')) {
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
