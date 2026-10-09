<!-- src/views/RunView.vue -->
<script setup>
import { ref, onMounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useWorkflowStore } from '@/stores/workflow'

const route = useRoute()
const router = useRouter()
const workflowStore = useWorkflowStore()

const workflowId = route.params.id
const formConfig = ref([])
const formData = ref({})
const isExecuting = ref(false)

onMounted(async () => {
  formConfig.value = workflowStore.getActiveFormConfig(workflowId)
  if (formConfig.value.length === 0) {
    alert('未找到有效的表单配置，请先进行装配')
    router.replace(`/workflow/${workflowId}`)
    return
  }

  if (!workflowStore.currentWorkflowData) {
    if (workflowId === 'local') {
      alert('本地模板数据已丢失，请重新返回首页导入')
      router.replace('/')
      return
    }
    await workflowStore.fetchWorkflowContent(workflowId)
  }

  formConfig.value.forEach((node) => {
    formData.value[node.id] = ''
    if (node.key === 'seed') generateSeed(node.id)
  })

  // 确保 WebSocket 长连接存活，为跳转后的记录页做准备
  workflowStore.connectWebSocket()
})

const generateSeed = (nodeId) => {
  formData.value[nodeId] = Math.floor(Math.random() * 9007199254740991)
}

const handleFileChange = (nodeId, event) => {
  const file = event.target.files[0]
  if (file) formData.value[nodeId] = file
}

const handleExecute = async () => {
  if (!workflowStore.currentWorkflowData) return

  isExecuting.value = true
  workflowStore.connectWebSocket() // 下发前强制保活

  try {
    const originalJson = JSON.parse(JSON.stringify(workflowStore.currentWorkflowData))
    const promptNodes = originalJson.prompt ? originalJson.prompt : originalJson

    for (const node of formConfig.value) {
      const nodeId = node.id
      const key = node.key
      let value = formData.value[nodeId]

      if (key === 'image' && value instanceof File) {
        const uploadedName = await workflowStore.uploadImage(value)
        if (!uploadedName) throw new Error('图片上传失败')
        value = uploadedName
      }

      if (key === 'seed') value = Number(value)

      if (value !== '' && value !== null && value !== undefined) {
        if (promptNodes[nodeId] && promptNodes[nodeId].inputs) {
          promptNodes[nodeId].inputs[key] = value
        }
      }
    }

    const result = await workflowStore.executeWorkflow(promptNodes)

    if (result && result.prompt_id) {
      workflowStore.createNewTask(result.prompt_id, workflowId)
      // 下发成功，直接跳转历史记录页看进度
      router.push('/history')
    } else {
      throw new Error('提交失败，请检查 ComfyUI 日志')
    }
  } catch (err) {
    alert(err.message || '执行过程出现异常')
    isExecuting.value = false
  }
}
</script>

<template>
  <div class="run-container">
    <div class="header">
      <button class="icon-btn" @click="router.replace('/')">🏠</button>
      <div class="title-area">
        <h2>运行: {{ workflowId.replace('_api.json', '') }}</h2>
        <span class="status-dot" :class="{ connected: workflowStore.isWsConnected }"></span>
      </div>
      <button class="icon-btn" @click="router.replace(`/workflow/${workflowId}`)">⚙️</button>
    </div>

    <div class="dynamic-form">
      <div v-for="node in formConfig" :key="node.id" class="form-group">
        <label>{{ node.alias }}</label>
        <textarea
          v-if="node.key === 'text' || node.key === 'value'"
          v-model="formData[node.id]"
          rows="3"
          placeholder="请输入描述..."
        ></textarea>
        <div v-else-if="node.key === 'seed'" class="seed-group">
          <input type="number" v-model="formData[node.id]" />
          <button @click="generateSeed(node.id)">🎲 随机</button>
        </div>
        <div v-else-if="node.key === 'image'" class="image-upload">
          <input type="file" accept="image/*" @change="(e) => handleFileChange(node.id, e)" />
        </div>
      </div>
    </div>

    <div class="bottom-action">
      <button class="execute-btn" @click="handleExecute" :disabled="isExecuting">
        {{ isExecuting ? '下发任务中...' : '🚀 立即生成' }}
      </button>
    </div>
  </div>
</template>

<style scoped>
.run-container {
  padding: 20px;
  padding-bottom: 140px;
}
.header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 16px;
}
.title-area {
  display: flex;
  align-items: center;
  gap: 8px;
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
.icon-btn {
  background: none;
  border: none;
  font-size: 20px;
  cursor: pointer;
  padding: 4px;
}
h2 {
  font-size: 18px;
  margin: 0;
  color: #333;
  font-weight: bold;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  max-width: 180px;
}
.form-group {
  margin-bottom: 20px;
  background: white;
  padding: 16px;
  border-radius: 12px;
  box-shadow: 0 1px 4px rgba(0, 0, 0, 0.03);
}
label {
  display: block;
  font-size: 14px;
  font-weight: bold;
  color: #444;
  margin-bottom: 10px;
}
textarea {
  width: 100%;
  padding: 10px;
  font-size: 14px;
  border: 1px solid #ddd;
  border-radius: 8px;
  box-sizing: border-box;
  resize: vertical;
}
.seed-group {
  display: flex;
  gap: 10px;
}
.seed-group input {
  flex: 1;
  padding: 10px;
  border: 1px solid #ddd;
  border-radius: 8px;
  font-size: 14px;
}
.seed-group button {
  padding: 0 16px;
  background: #f0f0f0;
  border: none;
  border-radius: 8px;
  cursor: pointer;
  white-space: nowrap;
}
.image-upload input {
  width: 100%;
  font-size: 14px;
}
.bottom-action {
  position: fixed;
  bottom: 60px;
  left: 0;
  width: 100%;
  padding: 16px;
  background: white;
  border-top: 1px solid #eee;
  box-sizing: border-box;
  z-index: 10;
}
.execute-btn {
  width: 100%;
  padding: 16px;
  font-size: 18px;
  font-weight: bold;
  background: linear-gradient(135deg, #4caf50, #45a049);
  color: white;
  border: none;
  border-radius: 12px;
  cursor: pointer;
  box-shadow: 0 4px 12px rgba(76, 175, 80, 0.3);
  transition: all 0.2s;
}
.execute-btn:disabled {
  background: #9e9e9e;
  box-shadow: none;
  cursor: not-allowed;
}
.execute-btn:active:not(:disabled) {
  transform: scale(0.98);
}
</style>
