<!-- src/views/SetupView.vue -->
<script setup>
import { ref } from 'vue'
import { useConfigStore } from '@/stores/config'

const configStore = useConfigStore()
const inputUrl = ref(configStore.comfyUrl)
const testResult = ref('')

const handleConnect = async () => {
  if (!inputUrl.value) {
    testResult.value = '请输入地址'
    return
  }
  const result = await configStore.testConnection(inputUrl.value)
  testResult.value = result.message
}
</script>

<template>
  <div class="setup-container">
    <h2>服务器配置</h2>
    <p class="desc">请输入您的 ComfyUI 服务地址（包含端口）。</p>

    <div class="form-group">
      <input
        v-model="inputUrl"
        type="text"
        placeholder="例如: http://192.168.1.100:8190"
        :disabled="configStore.isTesting"
      />
    </div>

    <button @click="handleConnect" :disabled="configStore.isTesting">
      {{ configStore.isTesting ? '连接中...' : '测试并保存连接' }}
    </button>

    <div
      v-if="testResult"
      class="result"
      :class="{ success: configStore.isConnected, error: !configStore.isConnected }"
    >
      {{ testResult }}
    </div>
  </div>
</template>

<style scoped>
.setup-container {
  padding: 20px;
  max-width: 600px;
  margin: 0 auto;
}
h2 {
  font-size: 24px;
  margin-bottom: 8px;
}
.desc {
  color: #666;
  font-size: 14px;
  margin-bottom: 24px;
}
.form-group {
  margin-bottom: 20px;
}
input {
  width: 100%;
  padding: 12px;
  font-size: 16px;
  border: 1px solid #ddd;
  border-radius: 8px;
  box-sizing: border-box;
}
button {
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
button:disabled {
  background-color: #a5d6a7;
}
.result {
  margin-top: 16px;
  padding: 12px;
  border-radius: 8px;
  text-align: center;
}
.success {
  background-color: #e8f5e9;
  color: #2e7d32;
}
.error {
  background-color: #ffebee;
  color: #c62828;
}
</style>
