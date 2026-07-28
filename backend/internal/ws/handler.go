package ws

import (
	"context"
	"encoding/json"
	"log"
	"net/http"

	"github.com/coder/websocket"
	"github.com/aroy/stashix/internal/auth"
)

// Router maps WS message types to handler funcs.
type Router struct {
	hub      *Hub
	handlers map[string]HandlerFunc
}

// HandlerFunc handles a WS request and returns a payload or error.
type HandlerFunc func(ctx context.Context, userID string, payload json.RawMessage) (any, error)

func NewRouter(hub *Hub) *Router {
	return &Router{hub: hub, handlers: make(map[string]HandlerFunc)}
}

func (r *Router) Handle(msgType string, fn HandlerFunc) {
	r.handlers[msgType] = fn
}

func (r *Router) ServeHTTP(w http.ResponseWriter, req *http.Request) {
	claims := auth.ClaimsFromCtx(req.Context())
	if claims == nil {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}

	conn, err := websocket.Accept(w, req, &websocket.AcceptOptions{
		InsecureSkipVerify: true,
	})
	if err != nil {
		log.Printf("ws upgrade: %v", err)
		return
	}
	conn.SetReadLimit(maxMessageSize)

	client := NewClient(conn)
	r.hub.Register(claims.UserID, client)
	defer r.hub.Unregister(claims.UserID)

	go client.WritePump(req.Context())

	for {
		_, data, err := conn.Read(req.Context())
		if err != nil {
			break
		}

		var msg Message
		if err := json.Unmarshal(data, &msg); err != nil {
			continue
		}

		go r.dispatch(req.Context(), claims.UserID, msg)
	}
}

func (r *Router) dispatch(ctx context.Context, userID string, msg Message) {
	fn, ok := r.handlers[msg.Type]
	if !ok {
		if msg.ID != "" {
			r.hub.Send(userID, Message{
				ID:    msg.ID,
				Type:  msg.Type + "_error",
				Error: "unknown message type",
			})
		}
		return
	}

	result, err := fn(ctx, userID, msg.Payload)
	if msg.ID == "" {
		return // fire-and-forget, no response expected
	}

	resp := Message{ID: msg.ID, Type: msg.Type + "_result"}
	if err != nil {
		resp.Type = msg.Type + "_error"
		resp.Error = err.Error()
	} else if result != nil {
		b, _ := json.Marshal(result)
		resp.Payload = b
	}
	r.hub.Send(userID, resp)
}
