<!-- src/views/HomeView.vue -->
<script setup>
import { onMounted, ref } from 'vue'
import { useRouter } from 'vue-router'
import { useConfigStore } from '@/stores/config'
import { useWorkflowStore } from '@/stores/workflow'

const router = useRouter()
const configStore = useConfigStore()
const workflowStore = useWorkflowStore()
const fileInput = ref(null)

// 页面加载时自动拉取列表
onMounted(() => {
  if (configStore.isConnected) {
    workflowStore.fetchRemoteList()
  }
})

// 触发本地文件选择
const triggerFileInput = () => {
  fileInput.value.click()
}

// 处理本地 JSON 文件导入
const handleFileUpload = (event) => {
  const file = event.target.files[0]
  if (!file) return
  const reader = new FileReader()
  reader.onload = (e) => {
    try {
      workflowStore.currentWorkflowData = JSON.parse(e.target.result)
      // 本地文件统一用 local 作为 ID
      router.push('/workflow/local')
    } catch (err) {
      alert('JSON 文件解析失败')
    }
  }
  reader.readAsText(file)
  event.target.value = ''
}

// 点击线上列表卡片
const handleCardClick = (filename) => {
  // 带着文件名跳转到工作流装配页
  router.push(`/workflow/${filename}`)
}
</script>

<template>
  <div class="home-container">
    <div class="header">
      <h2>我的功能卡片</h2>
      <button
        v-if="configStore.isConnected"
        class="refresh-btn"
        @click="workflowStore.fetchRemoteList"
      >
        刷新列表
      </button>
    </div>

    <!-- 未连接提示 -->
    <div v-if="!configStore.isConnected" class="empty-state">
      <p>尚未连接到服务器</p>
      <button class="action-btn" @click="router.push('/setup')">前往设置</button>
    </div>

    <!-- 列表展示区 -->
    <div v-else class="workflow-list">
      <div v-if="workflowStore.isLoading" class="loading">加载中...</div>

      <div v-else-if="workflowStore.workflowList.length === 0" class="empty-state">
        <p>未在服务器找到带有 _api.json 后缀的工作流。</p>
      </div>

      <div
        v-else
        v-for="file in workflowStore.workflowList"
        :key="file"
        class="card"
        @click="handleCardClick(file)"
      >
        <div class="card-title">{{ file.replace('_api.json', '') }}</div>
        <div class="card-subtitle">API 模板</div>
      </div>
    </div>

    <!-- 兜底：本地导入按钮 -->
    <div class="local-import-section">
      <div class="divider"><span>或者</span></div>
      <button class="action-btn secondary" @click="triggerFileInput">导入本地 _api.json</button>
      <input
        type="file"
        ref="fileInput"
        accept=".json"
        style="display: none"
        @change="handleFileUpload"
      />
    </div>
  </div>
</template>

<style scoped>
.home-container {
  padding: 20px;
}
.header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 24px;
}
h2 {
  font-size: 24px;
  color: #333;
  margin: 0;
}
.refresh-btn {
  padding: 6px 12px;
  font-size: 14px;
  background: #eee;
  border: none;
  border-radius: 6px;
  cursor: pointer;
}

.empty-state {
  text-align: center;
  color: #888;
  padding: 40px 0;
}
.loading {
  text-align: center;
  color: #666;
  padding: 20px;
}

.card {
  background: white;
  padding: 20px;
  border-radius: 12px;
  margin-bottom: 16px;
  box-shadow: 0 2px 8px rgba(0, 0, 0, 0.05);
  cursor: pointer;
  border: 1px solid #f0f0f0;
  transition: transform 0.1s;
}
.card:active {
  transform: scale(0.98);
}
.card-title {
  font-size: 18px;
  font-weight: bold;
  color: #222;
  margin-bottom: 4px;
}
.card-subtitle {
  font-size: 12px;
  color: #999;
}

.local-import-section {
  margin-top: 40px;
}
.divider {
  text-align: center;
  position: relative;
  margin-bottom: 20px;
}
.divider::before {
  content: '';
  position: absolute;
  left: 0;
  top: 50%;
  width: 100%;
  height: 1px;
  background: #ddd;
  z-index: 1;
}
.divider span {
  background: #f9f9f9;
  padding: 0 10px;
  position: relative;
  z-index: 2;
  color: #999;
  font-size: 12px;
}

.action-btn {
  width: 100%;
  padding: 14px;
  font-size: 16px;
  font-weight: bold;
  background-color: #4caf50;
  color: white;
  border: none;
  border-radius: 8px;
  cursor: pointer;
}
.action-btn.secondary {
  background-color: #fff;
  color: #333;
  border: 1px solid #ddd;
}
</style>
