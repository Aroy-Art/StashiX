package ws

import (
	"encoding/json"
	"sync"
)

// Message is the envelope for all WS communication.
// id is non-empty for request/response, empty for push events.
type Message struct {
	ID      string          `json:"id,omitempty"`
	Type    string          `json:"type"`
	Payload json.RawMessage `json:"payload,omitempty"`
	Error   string          `json:"error,omitempty"`
}

type Hub struct {
	mu      sync.RWMutex
	clients map[string]*Client // key: userID
}

func NewHub() *Hub {
	return &Hub{clients: make(map[string]*Client)}
}

func (h *Hub) Register(userID string, c *Client) {
	h.mu.Lock()
	defer h.mu.Unlock()
	// close existing connection for same user (single session per user for MVP)
	if old, ok := h.clients[userID]; ok {
		old.close()
	}
	h.clients[userID] = c
}

func (h *Hub) Unregister(userID string) {
	h.mu.Lock()
	defer h.mu.Unlock()
	delete(h.clients, userID)
}

// Broadcast sends an event to all connected clients.
func (h *Hub) Broadcast(msg Message) {
	data, _ := json.Marshal(msg)
	h.mu.RLock()
	defer h.mu.RUnlock()
	for _, c := range h.clients {
		c.send(data)
	}
}

// Send delivers a message to a specific user.
func (h *Hub) Send(userID string, msg Message) {
	data, _ := json.Marshal(msg)
	h.mu.RLock()
	c, ok := h.clients[userID]
	h.mu.RUnlock()
	if ok {
		c.send(data)
	}
}
