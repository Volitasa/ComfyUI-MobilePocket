// src/stores/config.js
import { ref } from 'vue'
import { defineStore } from 'pinia'

export const useConfigStore = defineStore('config', () => {
  // 从本地存储读取历史地址，默认为空[cite: 14]
  const comfyUrl = ref(localStorage.getItem('comfyUrl') || 'http://127.0.0.1:8190')
  const isConnected = ref(false)
  const isTesting = ref(false)

  // 【新增】全局唯一的客户端 ID (基于随机字符串 + 当前时间戳)
  // 核心作用：WebSocket 通信的身份凭证。App 单次运行期间保持不变，
  // 确保 POST 下发的任务和 WebSocket 接收的进度能完美对应。
  // 【升级】从硬盘读取专属 ID，如果没有则生成并永久固化
  const getOrCreateClientId = () => {
    let id = localStorage.getItem('comfy_client_id')
    if (!id) {
      id = `mobile_${Math.random().toString(36).substring(2, 9)}_${Date.now()}`
      localStorage.setItem('comfy_client_id', id)
    }
    return id
  }
  const clientId = ref(getOrCreateClientId())

  // 测试并保存连接[cite: 14]
  const testConnection = async (url) => {
    isTesting.value = true
    isConnected.value = false

    // 移除末尾的反斜杠[cite: 14]
    const cleanUrl = url.replace(/\/$/, '')

    try {
      // 调用 ComfyUI 原生系统状态接口测试[cite: 14]
      const res = await fetch(`${cleanUrl}/system_stats`, {
        method: 'GET',
        // 设置较短的超时时间防止卡死（浏览器原生的简易超时实现）[cite: 14]
        signal: AbortSignal.timeout(5000),
      })

      if (res.ok) {
        isConnected.value = true
        comfyUrl.value = cleanUrl
        localStorage.setItem('comfyUrl', cleanUrl)
        return { success: true, message: '连接成功！' }
      } else {
        return { success: false, message: `连接失败: HTTP ${res.status}` }
      }
    } catch (error) {
      return { success: false, message: '无法连接到服务器，请检查地址或网络跨域设置。' }
    } finally {
      isTesting.value = false
    }
  }

  // 必须将新增的 clientId 导出供外部使用
  return { comfyUrl, isConnected, isTesting, clientId, testConnection }
})
