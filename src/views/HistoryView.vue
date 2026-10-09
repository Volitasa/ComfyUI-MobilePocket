<!-- src/views/HistoryView.vue -->
<script setup>
import { ref, onMounted } from 'vue'
import { useWorkflowStore } from '@/stores/workflow'
import { useConfigStore } from '@/stores/config'

const workflowStore = useWorkflowStore()
const configStore = useConfigStore()

onMounted(() => {
  workflowStore.connectWebSocket()
})

// === 工具函数 ===
const getMediaUrl = (mediaObj) => {
  const params = new URLSearchParams({
    filename: mediaObj.filename,
    subfolder: mediaObj.subfolder || '',
    type: mediaObj.type || 'output',
  })
  return `${configStore.comfyUrl}/view?${params.toString()}`
}

const isVideo = (filename) => {
  if (!filename) return false
  const ext = filename.split('.').pop().toLowerCase()
  return ['mp4', 'webm', 'mov'].includes(ext)
}

const removeTask = (index) => {
  const confirmDelete = window.confirm('确定要删除这条记录吗？')
  if (confirmDelete) {
    workflowStore.taskHistory.splice(index, 1)
    workflowStore.saveTaskHistory()
  }
}

// === 画廊大图浏览器逻辑 ===
const viewerState = ref({
  isOpen: false,
  mediaList: [],
  currentIndex: 0,
})

const openViewer = (images) => {
  if (!images || images.length === 0) return
  viewerState.value.mediaList = images
  viewerState.value.currentIndex = 0
  viewerState.value.isOpen = true
  document.body.style.overflow = 'hidden' // 防止穿透滚动
}

const closeViewer = () => {
  viewerState.value.isOpen = false
  viewerState.value.mediaList = []
  document.body.style.overflow = ''
}

const nextMedia = () => {
  if (viewerState.value.currentIndex < viewerState.value.mediaList.length - 1) {
    viewerState.value.currentIndex++
  }
}

const prevMedia = () => {
  if (viewerState.value.currentIndex > 0) {
    viewerState.value.currentIndex--
  }
}

// 滑动交互
const touchStartX = ref(0)
const onTouchStart = (e) => {
  touchStartX.value = e.changedTouches[0].clientX
}
const onTouchEnd = (e) => {
  const touchEndX = e.changedTouches[0].clientX
  if (touchStartX.value - touchEndX > 50) nextMedia() // 左滑下一张
  if (touchEndX - touchStartX.value > 50) prevMedia() // 右滑上一张
}

// 保存媒体到本地
const saveToLocal = async () => {
  try {
    const currentMedia = viewerState.value.mediaList[viewerState.value.currentIndex]
    const url = getMediaUrl(currentMedia)

    // 利用 Fetch 转 Blob 触发下载，兼容性好
    const response = await fetch(url)
    const blob = await response.blob()
    const downloadUrl = window.URL.createObjectURL(blob)

    const a = document.createElement('a')
    a.href = downloadUrl
    a.download = currentMedia.filename
    document.body.appendChild(a)
    a.click()
    document.body.removeChild(a)
    window.URL.revokeObjectURL(downloadUrl)
  } catch (error) {
    alert('保存失败，可能是跨域限制。')
  }
}
</script>

<template>
  <div class="history-container">
    <div class="header">
      <h2>生成记录</h2>
      <span class="status-dot" :class="{ connected: workflowStore.isWsConnected }"></span>
    </div>

    <div v-if="workflowStore.taskHistory.length === 0" class="empty-state">暂无生成记录</div>

    <!-- 任务卡片列表 -->
    <div v-for="(task, index) in workflowStore.taskHistory" :key="task.promptId" class="task-card">
      <div class="task-info">
        <div class="task-title-bar">
          <h3 class="task-title">{{ task.title }}</h3>
          <!-- 独立的删除按钮 -->
          <button class="delete-btn" @click="removeTask(index)">✕</button>
        </div>

        <div class="task-status" :class="{ done: task.status === '已完成' }">
          {{ task.status }} - {{ task.nodeInfo }}
        </div>

        <div class="progress-track" v-if="task.status !== '已完成'">
          <div
            class="progress-fill"
            :style="{
              width:
                task.progressMax > 0 ? (task.progressValue / task.progressMax) * 100 + '%' : '0%',
            }"
          ></div>
        </div>

        <div class="task-time">{{ new Date(task.timestamp).toLocaleString() }}</div>
      </div>

      <!-- 右侧缩略图区域 -->
      <div class="task-thumb" @click="openViewer(task.images)">
        <template v-if="task.images && task.images.length > 0">
          <!-- 视频或图片缩略图 -->
          <video
            v-if="isVideo(task.images[0].filename)"
            :src="getMediaUrl(task.images[0])"
            muted
            loop
            autoplay
            class="media-cover"
          ></video>
          <img v-else :src="getMediaUrl(task.images[0])" class="media-cover" />

          <!-- 多图/视频角标 -->
          <div v-if="task.images.length > 1" class="media-badge">
            {{ task.images.length }}
          </div>
        </template>

        <div v-else class="placeholder">
          <span v-if="task.status === '已完成'">无图</span>
          <span v-else class="loading-spinner"></span>
        </div>
      </div>
    </div>

    <!-- 全屏媒体浏览器 (Lightbox) -->
    <Teleport to="body">
      <div v-if="viewerState.isOpen" class="viewer-overlay">
        <!-- 顶部工具栏 -->
        <div class="viewer-header">
          <span class="viewer-counter">
            {{ viewerState.currentIndex + 1 }} / {{ viewerState.mediaList.length }}
          </span>
          <button class="close-viewer-btn" @click="closeViewer">✕</button>
        </div>

        <!-- 媒体展示区 (支持滑动) -->
        <div class="viewer-content" @touchstart="onTouchStart" @touchend="onTouchEnd">
          <video
            v-if="isVideo(viewerState.mediaList[viewerState.currentIndex].filename)"
            :src="getMediaUrl(viewerState.mediaList[viewerState.currentIndex])"
            controls
            autoplay
            loop
            class="viewer-media"
          ></video>
          <img
            v-else
            :src="getMediaUrl(viewerState.mediaList[viewerState.currentIndex])"
            class="viewer-media"
          />
        </div>

        <!-- 底部控制栏 -->
        <div class="viewer-footer">
          <button
            class="viewer-nav-btn"
            :disabled="viewerState.currentIndex === 0"
            @click="prevMedia"
          >
            上一张
          </button>
          <button class="viewer-save-btn" @click="saveToLocal">💾 保存到本地</button>
          <button
            class="viewer-nav-btn"
            :disabled="viewerState.currentIndex === viewerState.mediaList.length - 1"
            @click="nextMedia"
          >
            下一张
          </button>
        </div>
      </div>
    </Teleport>
  </div>
</template>

<style scoped>
.history-container {
  padding: 20px;
  padding-bottom: 80px;
}
.header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 24px;
}
h2 {
  font-size: 24px;
  margin: 0;
  color: #333;
}
.status-dot {
  width: 10px;
  height: 10px;
  border-radius: 50%;
  background-color: #ff4d4f;
  transition: all 0.3s;
}
.status-dot.connected {
  background-color: #52c41a;
  box-shadow: 0 0 8px rgba(82, 196, 26, 0.6);
}
.empty-state {
  text-align: center;
  padding: 40px;
  color: #999;
}

/* 任务卡片样式 */
.task-card {
  display: flex;
  background: white;
  border-radius: 12px;
  padding: 16px;
  margin-bottom: 16px;
  box-shadow: 0 2px 8px rgba(0, 0, 0, 0.05);
  border: 1px solid #f0f0f0;
}
.task-info {
  flex: 1;
  padding-right: 16px;
  overflow: hidden;
  display: flex;
  flex-direction: column;
  justify-content: center;
}
.task-title-bar {
  display: flex;
  justify-content: space-between;
  align-items: flex-start;
  margin-bottom: 8px;
}
.task-title {
  font-size: 16px;
  font-weight: bold;
  color: #222;
  margin: 0;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  flex: 1;
}
.delete-btn {
  background: none;
  border: none;
  color: #ccc;
  font-size: 16px;
  padding: 0 4px;
  cursor: pointer;
}
.delete-btn:active {
  color: #f44336;
}
.task-status {
  font-size: 13px;
  color: #f57c00;
  margin-bottom: 8px;
}
.task-status.done {
  color: #4caf50;
}
.task-time {
  font-size: 11px;
  color: #999;
  margin-top: 8px;
}

/* 进度条 */
.progress-track {
  width: 100%;
  height: 6px;
  background: #e0e0e0;
  border-radius: 3px;
  overflow: hidden;
}
.progress-fill {
  height: 100%;
  background: #4caf50;
  transition: width 0.3s ease;
}

/* 缩略图 */
.task-thumb {
  width: 80px;
  height: 80px;
  flex-shrink: 0;
  border-radius: 8px;
  overflow: hidden;
  background: #f8f9fa;
  position: relative;
  border: 1px solid #eee;
  cursor: pointer;
}
.media-cover {
  width: 100%;
  height: 100%;
  object-fit: cover;
}
.media-badge {
  position: absolute;
  bottom: 4px;
  right: 4px;
  background: rgba(0, 0, 0, 0.6);
  color: white;
  font-size: 10px;
  padding: 2px 6px;
  border-radius: 10px;
  font-weight: bold;
}
.placeholder {
  width: 100%;
  height: 100%;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 12px;
  color: #999;
}
.loading-spinner {
  width: 20px;
  height: 20px;
  border: 2px solid #ddd;
  border-top-color: #4caf50;
  border-radius: 50%;
  animation: spin 1s linear infinite;
}
@keyframes spin {
  to {
    transform: rotate(360deg);
  }
}

/* 全屏画廊 Viewer */
.viewer-overlay {
  position: fixed;
  top: 0;
  left: 0;
  width: 100vw;
  height: 100vh;
  background: rgba(0, 0, 0, 0.95);
  z-index: 9999;
  display: flex;
  flex-direction: column;
}
.viewer-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 20px;
  color: white;
}
.viewer-counter {
  font-size: 16px;
  font-weight: bold;
  letter-spacing: 2px;
}
.close-viewer-btn {
  background: none;
  border: none;
  color: white;
  font-size: 24px;
  cursor: pointer;
}
.viewer-content {
  flex: 1;
  display: flex;
  justify-content: center;
  align-items: center;
  overflow: hidden;
}
.viewer-media {
  max-width: 100%;
  max-height: 100%;
  object-fit: contain;
}
.viewer-footer {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 20px 30px;
  padding-bottom: max(20px, env(safe-area-inset-bottom));
}
.viewer-nav-btn {
  background: none;
  border: none;
  color: white;
  font-size: 14px;
  opacity: 0.8;
}
.viewer-nav-btn:disabled {
  opacity: 0.2;
}
.viewer-save-btn {
  background: #4caf50;
  border: none;
  color: white;
  padding: 10px 20px;
  border-radius: 20px;
  font-weight: bold;
  font-size: 14px;
}
</style>
