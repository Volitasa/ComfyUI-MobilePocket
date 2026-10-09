<!-- src/App.vue -->
<script setup>
import { RouterView, RouterLink } from 'vue-router'
</script>

<template>
  <div class="app-layout">
    <!-- 主体内容区 -->
    <main class="main-content">
      <RouterView />
    </main>

    <!-- 底部导航栏 -->
    <nav class="bottom-nav">
      <RouterLink to="/" class="nav-item" active-class="active">首页</RouterLink>
      <RouterLink to="/history" class="nav-item" active-class="active">生成记录</RouterLink>
      <RouterLink to="/setup" class="nav-item" active-class="active">设置</RouterLink>
    </nav>
  </div>
</template>

<style>
/* 全局基础重置 */
body,
html {
  margin: 0;
  padding: 0;
  font-family: -apple-system, sans-serif;
  background-color: #f9f9f9;
}
</style>

<style scoped>
.app-layout {
  display: flex;
  flex-direction: column;
  height: 100vh;
}
.main-content {
  flex: 1;
  overflow-y: auto;
  padding-bottom: 60px; /* 留出底部导航空间 */
}
.bottom-nav {
  position: fixed;
  bottom: 0;
  width: 100%;
  height: 60px;
  background: white;
  border-top: 1px solid #eee;
  display: flex;
  justify-content: space-around;
  align-items: center;
  box-shadow: 0 -2px 10px rgba(0, 0, 0, 0.05);
  z-index: 100;
}
.nav-item {
  text-decoration: none;
  color: #888;
  font-size: 14px;
  font-weight: 500;
}
.nav-item.active {
  color: #4caf50;
}
</style>
