import { createRouter, createWebHistory } from 'vue-router'

const routes = [
  { path: '/', name: 'Home', component: () => import('@/pages/HomePage.vue') },
  { path: '/play', name: 'Play', component: () => import('@/pages/PlayPage.vue') },
  { path: '/online', name: 'Online', component: () => import('@/pages/OnlinePage.vue') },
  { path: '/room/:code', name: 'Room', component: () => import('@/pages/RoomPage.vue') },
  { path: '/settings', name: 'Settings', component: () => import('@/pages/SettingsPage.vue') },
  { path: '/team-select', name: 'TeamSelect', component: () => import('@/pages/TeamSelectPage.vue') },
]

const router = createRouter({
  history: createWebHistory(),
  routes
})

export default router
