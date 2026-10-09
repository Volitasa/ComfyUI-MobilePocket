// src/stores/workflow.js
import { ref } from 'vue'
import { defineStore } from 'pinia'
import { useConfigStore } from './config'

export const useWorkflowStore = defineStore('workflow', () => {
  const configStore = useConfigStore()

  const workflowList = ref([])
  const isLoading = ref(false)
  const currentWorkflowData = ref(null)

  const ws = ref(null)
  const isWsConnected = ref(false)

  const taskHistory = ref(JSON.parse(localStorage.getItem('comfy_task_history') || '[]'))

  const saveTaskHistory = () => {
    localStorage.setItem('comfy_task_history', JSON.stringify(taskHistory.value))
  }

  const createNewTask = (promptId, workflowId) => {
    taskHistory.value.unshift({
      promptId,
      workflowId,
      title: workflowId.replace('_api.json', ''),
      status: '排队中',
      progressValue: 0,
      progressMax: 0,
      nodeInfo: '等待执行...',
      images: [],
      timestamp: Date.now(),
    })
    if (taskHistory.value.length > 50) taskHistory.value.pop()
    saveTaskHistory()
  }

  const connectWebSocket = () => {
    if (ws.value && isWsConnected.value) return

    let wsUrl = ''
    if (configStore.comfyUrl.startsWith('/api')) {
      const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:'
      wsUrl = `${protocol}//${window.location.host}/api/ws?clientId=${configStore.clientId}`
    } else {
      const protocol = configStore.comfyUrl.startsWith('https') ? 'wss:' : 'ws:'
      const host = configStore.comfyUrl.replace(/^https?:\/\//, '')
      wsUrl = `${protocol}//${host}/ws?clientId=${configStore.clientId}`
    }

    ws.value = new WebSocket(wsUrl)

    ws.value.onopen = () => {
      isWsConnected.value = true
    }

    ws.value.onmessage = (event) => {
      if (typeof event.data === 'string') {
        const msg = JSON.parse(event.data)

        if (!msg.data || !msg.data.prompt_id) return
        const task = taskHistory.value.find((t) => t.promptId === msg.data.prompt_id)
        if (!task) return

        if (msg.type === 'execution_start') {
          task.status = '生成中'
          task.nodeInfo = '🚀 任务开始...'
        } else if (msg.type === 'execution_cached') {
          task.status = '生成中'
          task.nodeInfo = '⚡ 命中缓存...'
        } else if (msg.type === 'progress') {
          task.progressValue = msg.data.value
          task.progressMax = msg.data.max
          task.nodeInfo = '🔄 处理节点...'
        } else if (msg.type === 'executing') {
          if (msg.data.node) {
            task.nodeInfo = `执行: ${msg.data.node}`
          } else {
            task.status = '已完成'
            task.progressValue = task.progressMax
            task.nodeInfo = '✅ 流程结束'
          }
        } else if (msg.type === 'executed') {
          // 【核心修改】：同时兼容静态图片和视频/动图的输出收集
          if (msg.data.output) {
            if (msg.data.output.images) task.images.push(...msg.data.output.images)
            if (msg.data.output.gifs) task.images.push(...msg.data.output.gifs)
          }
          task.status = '已完成'
          task.nodeInfo = '✅ 生成成功'
        }

        saveTaskHistory()
      }
    }

    ws.value.onclose = () => {
      isWsConnected.value = false
      ws.value = null
    }
  }

  const fetchRemoteList = async () => {
    if (!configStore.isConnected) return
    isLoading.value = true
    try {
      const res = await fetch(`${configStore.comfyUrl}/userdata?dir=workflows`)
      if (res.ok) {
        const data = await res.json()
        const files = Array.isArray(data) ? data : data.files || []
        workflowList.value = files.filter((name) => name.endsWith('_api.json'))
      }
    } catch (error) {
      console.error(error)
    } finally {
      isLoading.value = false
    }
  }

  const fetchWorkflowContent = async (filename) => {
    try {
      const fileParam = encodeURIComponent(`workflows/${filename}`)
      const res = await fetch(`${configStore.comfyUrl}/userdata/${fileParam}`)
      if (res.ok) {
        currentWorkflowData.value = await res.json()
        return true
      }
    } catch (error) {
      console.error(error)
    }
    return false
  }

  const saveMappingConfig = (workflowId, config) => {
    localStorage.setItem(`mapping_${workflowId}`, JSON.stringify(config))
  }

  const getMappingConfig = (workflowId) => {
    const data = localStorage.getItem(`mapping_${workflowId}`)
    return data ? JSON.parse(data) : null
  }

  const getActiveFormConfig = (workflowId) => {
    const saved = getMappingConfig(workflowId)
    if (!saved) return []
    return saved.filter((node) => node.exposed)
  }

  const uploadImage = async (file) => {
    const formData = new FormData()
    formData.append('image', file)
    try {
      const res = await fetch(`${configStore.comfyUrl}/upload/image`, {
        method: 'POST',
        body: formData,
      })
      if (res.ok) {
        const data = await res.json()
        return data.name
      }
    } catch (error) {
      console.error(error)
    }
    return null
  }

  const executeWorkflow = async (promptNodes) => {
    const payload = { client_id: configStore.clientId, prompt: promptNodes }
    try {
      const res = await fetch(`${configStore.comfyUrl}/prompt`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload),
      })
      if (res.ok) {
        return await res.json()
      }
    } catch (error) {
      console.error(error)
    }
    return null
  }

  return {
    workflowList,
    isLoading,
    currentWorkflowData,
    ws,
    isWsConnected,
    taskHistory,
    connectWebSocket,
    createNewTask,
    saveTaskHistory,
    fetchRemoteList,
    fetchWorkflowContent,
    saveMappingConfig,
    getMappingConfig,
    getActiveFormConfig,
    uploadImage,
    executeWorkflow,
  }
})
