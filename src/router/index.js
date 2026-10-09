// src/router/index.js
import { createRouter, createWebHistory } from 'vue-router'
import HomeView from '../views/HomeView.vue'
import SetupView from '../views/SetupView.vue'
import WorkflowView from '../views/WorkflowView.vue'
import RunView from '../views/RunView.vue'
import HistoryView from '../views/HistoryView.vue'

const router = createRouter({
  history: createWebHistory(import.meta.env.BASE_URL),
  routes: [
    { path: '/', name: 'home', component: HomeView },
    { path: '/setup', name: 'setup', component: SetupView },
    { path: '/workflow/:id', name: 'workflow', component: WorkflowView },
    { path: '/run/:id', name: 'run', component: RunView },
    { path: '/history', name: 'history', component: HistoryView },
  ],
})

export default router
