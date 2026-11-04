import { defineStore } from 'pinia'
import { ref, computed } from 'vue'

export const useMatchmakingStore = defineStore('matchmaking', () => {
  // Room state
  const roomCode = ref(null)
  const roomId = ref(null)
  const isInRoom = ref(false)
  const isHost = ref(false)
  const opponent = ref(null)
  const status = ref('disconnected') // disconnected, connecting, waiting, ready, playing
  const channel = ref(null)
  
  // Multiplayer support
  const capacity = ref(2) // 2, 4, or 6 players
  const teamSize = computed(() => capacity.value / 2)
  const players = ref([]) // All players in room
  const spectators = ref(0)
  
  // Room settings
  const roomSettings = ref({
    field: 'stadium',
    ball: 0,
    matchTime: 300,
    turnTime: 15,
    public: false,
    name: ''
  })
  
  // Match settings from server
  const matchSettings = ref(null)
  const matchReservation = ref(null)
  
  // Spectator mode
  const isSpectator = ref(false)
  const spectatingMatchId = ref(null)

  function generateCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'
    let c = ''
    for (let i = 0; i < 6; i++) c += chars[Math.floor(Math.random() * chars.length)]
    return c
  }

  // Create a new room
  async function createRoom(options = {}) {
    const player = usePlayerStore()
    status.value = 'connecting'
    
    try {
      const response = await fetch('/rooms', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ' + localStorage.getItem('bnxg_token')
        },
        body: JSON.stringify({
          name: options.name || `${player.profile.name}'s Room`,
          public: options.public || false,
          capacity: options.capacity || 2,
          field: options.field || player.profile.equip?.field || 'stadium',
          ball: options.ball !== undefined ? options.ball : (player.profile.equip?.ball || 0),
          matchTime: options.matchTime || 300
        })
      })
      
      if (!response.ok) throw new Error('Failed to create room')
      
      const data = await response.json()
      roomCode.value = data.code
      roomId.value = data.roomId
      isHost.value = true
      capacity.value = data.capacity || 2
      isInRoom.value = true
      status.value = 'waiting'
      
      // Update room settings
      roomSettings.value = {
        field: options.field || 'stadium',
        ball: options.ball || 0,
        matchTime: options.matchTime || 300,
        public: options.public || false,
        name: options.name || ''
      }
      
      players.value = [{
        id: player.profile.id,
        name: player.profile.name,
        team: 0,
        slot: 0,
        ready: false,
        connected: true,
        isHost: true
      }]
      
      return data.code
    } catch (e) {
      console.error('Create room failed:', e)
      status.value = 'disconnected'
      throw e
    }
  }

  // Join existing room by code
  async function joinRoom(code) {
    const player = usePlayerStore()
    status.value = 'connecting'
    
    try {
      const response = await fetch('/rooms/join', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ' + localStorage.getItem('bnxg_token')
        },
        body: JSON.stringify({ code: code.toUpperCase() })
      })
      
      if (!response.ok) {
        const err = await response.json()
        throw new Error(err.error || 'Room not found')
      }
      
      const data = await response.json()
      roomCode.value = data.code
      capacity.value = data.capacity || 2
      isHost.value = false
      isInRoom.value = true
      status.value = 'waiting'
      
      // Add self to players
      const myTeam = players.value.length < teamSize.value ? 0 : 1
      const slotInTeam = players.value.filter(p => p.team === myTeam).length
      
      players.value.push({
        id: player.profile.id,
        name: player.profile.name,
        team: myTeam,
        slot: slotInTeam,
        ready: false,
        connected: true,
        isHost: false
      })
      
      return data.code
    } catch (e) {
      status.value = 'disconnected'
      throw e
    }
  }

  // Join matchmaking queue
  async function joinQueue(mode = '1v1') {
    const player = usePlayerStore()
    status.value = 'searching'
    
    try {
      const response = await fetch('/matchmaking/join', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ' + localStorage.getItem('bnxg_token')
        },
        body: JSON.stringify({ mode })
      })
      
      if (!response.ok) throw new Error('Failed to join queue')
      
      status.value = 'searching'
      return true
    } catch (e) {
      status.value = 'disconnected'
      throw e
    }
  }

  // Cancel matchmaking queue
  async function cancelQueue() {
    try {
      await fetch('/matchmaking/cancel', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ' + localStorage.getItem('bnxg_token')
        }
      })
      status.value = 'disconnected'
    } catch (e) {
      console.error('Cancel queue failed:', e)
    }
  }

  // Set player ready status
  async function setReady(ready) {
    if (!isInRoom.value) return
    
    const player = usePlayerStore()
    const myPlayer = players.value.find(p => p.id === player.profile.id)
    if (myPlayer) myPlayer.ready = ready
    
    // Notify server
    if (window.NexoraBackend?.rooms) {
      await window.NexoraBackend.rooms.setReady(ready)
    }
    
    // Check if all players ready
    checkAllReady()
  }

  function checkAllReady() {
    if (players.value.every(p => p.ready)) {
      status.value = 'ready'
    }
  }

  // Start match (host only)
  async function startMatch() {
    if (!isHost.value || !matchReservation.value) return
    
    try {
      if (window.NexoraBackend?.rooms) {
        const result = await window.NexoraBackend.rooms.start()
        return result
      }
    } catch (e) {
      console.error('Start match failed:', e)
      throw e
    }
  }

  // Leave current room/queue
  async function leaveRoom() {
    if (channel.value) {
      await window.supabase?.removeChannel(channel.value)
      channel.value = null
    }
    
    if (window.NexoraBackend?.rooms && isInRoom.value) {
      try {
        await window.NexoraBackend.rooms.leave()
      } catch (e) {}
    }
    
    reset()
  }

  // Join as spectator
  async function joinSpectator(matchId) {
    isSpectator.value = true
    spectatingMatchId.value = matchId
    status.value = 'spectating'
  }

  // Leave spectator mode
  async function leaveSpectator() {
    isSpectator.value = false
    spectatingMatchId.value = null
    status.value = 'disconnected'
  }

  function reset() {
    roomCode.value = null
    roomId.value = null
    isInRoom.value = false
    isHost.value = false
    opponent.value = null
    status.value = 'disconnected'
    channel.value = null
    capacity.value = 2
    players.value = []
    spectators.value = 0
    matchSettings.value = null
    matchReservation.value = null
    isSpectator.value = false
    spectatingMatchId.value = null
  }

  // Computed helpers
  const myTeam = computed(() => {
    const player = usePlayerStore()
    return players.value.filter(p => p.id === player.profile.id)[0]?.team ?? 0
  })
  
  const teammates = computed(() => {
    return players.value.filter(p => p.team === myTeam.value)
  })
  
  const opponents = computed(() => {
    return players.value.filter(p => p.team !== myTeam.value)
  })
  
  const roomFull = computed(() => {
    return players.value.length >= capacity.value
  })

  return {
    // State
    roomCode, roomId, isInRoom, isHost, status, capacity, teamSize,
    players, spectators, roomSettings, matchSettings, matchReservation,
    isSpectator, spectatingMatchId,
    
    // Computed
    myTeam, teammates, opponents, roomFull,
    
    // Actions
    generateCode,
    createRoom, joinRoom, leaveRoom,
    joinQueue, cancelQueue,
    setReady, startMatch,
    joinSpectator, leaveSpectator,
    reset
  }
})

// Lazy import to avoid circular dependency
import { usePlayerStore } from './player'
