<!-- src/views/WorkflowView.vue -->
<script setup>
import { ref, onMounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useWorkflowStore } from '@/stores/workflow'

const route = useRoute()
const router = useRouter()
const workflowStore = useWorkflowStore()

const workflowId = route.params.id
const isReady = ref(false)

// 提取出来的可配置节点列表
const extractableNodes = ref([])

onMounted(async () => {
  // 场景 1：本地导入模式 (必须确保内存中有从首页传来的数据)
  if (workflowId === 'local') {
    if (!workflowStore.currentWorkflowData) {
      alert('本地数据已丢失，请重新选择文件')
      router.replace('/')
    } else {
      parseWorkflow(workflowStore.currentWorkflowData)
      isReady.value = true
    }
    return
  }

  // 场景 2：线上拉取模式 (无视旧内存，每次进入必定重新请求)
  const success = await workflowStore.fetchWorkflowContent(workflowId)
  if (!success) {
    alert('拉取线上工作流内容失败，请检查服务器连接')
    router.back()
    return
  }

  parseWorkflow(workflowStore.currentWorkflowData)
  isReady.value = true
})

// 核心魔法：解析 JSON 提取节点 (升级增强版)
const parseWorkflow = (json) => {
  const nodes = []

  for (const [nodeId, node] of Object.entries(json)) {
    // 1. 提取 KSampler 的随机种子
    if (node.class_type === 'KSampler' || node.class_type === 'KSamplerAdvanced') {
      // 必须确保 seed 是直接填写的数值，而不是被其他节点连过来的线（数组格式）
      if (node.inputs.seed !== undefined && !Array.isArray(node.inputs.seed)) {
        nodes.push({
          id: nodeId,
          classType: node.class_type,
          key: 'seed',
          alias: node._meta?.title || `随机种子 ${nodeId}`,
          exposed: true,
        })
      }
    }
    // 2. 提取原生 CLIP 文本
    else if (node.class_type === 'CLIPTextEncode') {
      // 必须确保 text 是纯字符串，如果连了线（比如 ["18", 0]）则跳过，防止破坏工作流
      if (node.inputs.text !== undefined && typeof node.inputs.text === 'string') {
        nodes.push({
          id: nodeId,
          classType: node.class_type,
          key: 'text',
          alias: node._meta?.title || `提示词 ${nodeId}`,
          exposed: true,
        })
      }
    }
    // 3. 提取主流自定义文本节点 (支持你的 Text Multiline 以及通用的 PrimitiveNode)
    else if (['Text Multiline', 'Text box', 'PrimitiveNode'].includes(node.class_type)) {
      if (node.inputs.text !== undefined && typeof node.inputs.text === 'string') {
        nodes.push({
          id: nodeId,
          classType: node.class_type,
          key: 'text',
          alias: node._meta?.title || `文本参数 ${nodeId}`,
          exposed: true,
        })
      } else if (node.inputs.value !== undefined && typeof node.inputs.value === 'string') {
        nodes.push({
          id: nodeId,
          classType: node.class_type,
          key: 'value',
          alias: node._meta?.title || `基础参数 ${nodeId}`,
          exposed: true,
        })
      }
    }
    // 4. 提取图片上传节点
    else if (node.class_type === 'LoadImage') {
      if (node.inputs.image !== undefined && typeof node.inputs.image === 'string') {
        nodes.push({
          id: nodeId,
          classType: node.class_type,
          key: 'image',
          alias: node._meta?.title || `上传图片 ${nodeId}`,
          exposed: true,
        })
      }
    }
  }

  // 增加缓存防空死锁机制：只有当缓存存在且真的有内容时，才使用历史缓存
  const savedConfig = workflowStore.getMappingConfig(workflowId)
  if (savedConfig && savedConfig.length > 0) {
    extractableNodes.value = savedConfig
  } else {
    extractableNodes.value = nodes
  }
}

// 保存配置
const handleSaveMapping = () => {
  workflowStore.saveMappingConfig(workflowId, extractableNodes.value)
  router.push(`/run/${workflowId}`) // 保存后直接进入运行页
}
</script>

<template>
  <div class="workflow-container" v-if="isReady">
    <div class="header">
      <button class="back-btn" @click="router.back()">← 返回</button>
      <h2>配置面板: {{ workflowId.replace('_api.json', '') }}</h2>
    </div>

    <div class="mapping-section">
      <p class="desc">请勾选需要暴露到手机 App 表单的参数，并为它们起一个易懂的名字。</p>

      <div v-for="node in extractableNodes" :key="node.id" class="mapping-item">
        <div class="item-header">
          <label class="checkbox-label">
            <input type="checkbox" v-model="node.exposed" />
            <span class="node-type">[{{ node.classType }}] Node: {{ node.id }}</span>
          </label>
        </div>

        <div class="item-body" v-if="node.exposed">
          <span class="param-key">参数: {{ node.key }}</span>
          <input v-model="node.alias" class="alias-input" placeholder="例如: 画面主体描述" />
        </div>
      </div>

      <div v-if="extractableNodes.length === 0" class="empty-state">
        此工作流没有找到支持动态修改的节点（缺少提示词、图片加载或采样器）。
      </div>
    </div>

    <div class="bottom-action">
      <button class="save-btn" @click="handleSaveMapping">保存表单配置</button>
    </div>
  </div>
</template>

<style scoped>
.workflow-container {
  padding: 20px;
  padding-bottom: 140px;
}
.header {
  display: flex;
  align-items: center;
  margin-bottom: 20px;
}
.back-btn {
  background: none;
  border: none;
  font-size: 16px;
  color: #4caf50;
  margin-right: 12px;
  cursor: pointer;
  padding: 0;
}
h2 {
  font-size: 18px;
  margin: 0;
  color: #333;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.desc {
  font-size: 14px;
  color: #666;
  margin-bottom: 20px;
  line-height: 1.5;
}

.mapping-item {
  background: #fff;
  border: 1px solid #eee;
  border-radius: 8px;
  padding: 16px;
  margin-bottom: 12px;
  box-shadow: 0 1px 4px rgba(0, 0, 0, 0.02);
}
.item-header {
  display: flex;
  align-items: center;
  margin-bottom: 12px;
}
.checkbox-label {
  display: flex;
  align-items: center;
  cursor: pointer;
}
.checkbox-label input {
  width: 18px;
  height: 18px;
  margin-right: 10px;
}
.node-type {
  font-weight: bold;
  color: #444;
  font-size: 15px;
}

.item-body {
  display: flex;
  flex-direction: column;
  padding-left: 28px;
}
.param-key {
  font-size: 12px;
  color: #888;
  margin-bottom: 6px;
}
.alias-input {
  padding: 10px;
  font-size: 14px;
  border: 1px solid #ccc;
  border-radius: 6px;
}

.bottom-action {
  position: fixed;
  bottom: 60px; /* 避开底部导航栏 */
  left: 0;
  width: 100%;
  padding: 16px;
  background: white;
  border-top: 1px solid #eee;
  box-sizing: border-box;
  z-index: 10;
}
.save-btn {
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

.empty-state {
  text-align: center;
  color: #999;
  padding: 30px;
  font-size: 14px;
}
</style>
