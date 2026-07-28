package ws

import (
	"context"
	"time"

	"github.com/coder/websocket"
)

const (
	writeWait      = 10 * time.Second
	pongWait       = 60 * time.Second
	pingPeriod     = (pongWait * 9) / 10
	maxMessageSize = 64 * 1024
)

type Client struct {
	conn   *websocket.Conn
	sendCh chan []byte
	done   chan struct{}
}

func NewClient(conn *websocket.Conn) *Client {
	return &Client{
		conn:   conn,
		sendCh: make(chan []byte, 64),
		done:   make(chan struct{}),
	}
}

func (c *Client) send(data []byte) {
	select {
	case c.sendCh <- data:
	default:
		// slow client — drop message rather than block
	}
}

func (c *Client) close() {
	select {
	case <-c.done:
	default:
		close(c.done)
		c.conn.Close(websocket.StatusNormalClosure, "")
	}
}

// WritePump pumps messages from sendCh to the websocket.
func (c *Client) WritePump(ctx context.Context) {
	ticker := time.NewTicker(pingPeriod)
	defer func() {
		ticker.Stop()
		c.conn.Close(websocket.StatusNormalClosure, "")
	}()
	for {
		select {
		case data, ok := <-c.sendCh:
			if !ok {
				c.conn.Close(websocket.StatusNormalClosure, "")
				return
			}
			writeCtx, cancel := context.WithTimeout(ctx, writeWait)
			err := c.conn.Write(writeCtx, websocket.MessageText, data)
			cancel()
			if err != nil {
				return
			}
		case <-ticker.C:
			pingCtx, cancel := context.WithTimeout(ctx, writeWait)
			err := c.conn.Ping(pingCtx)
			cancel()
			if err != nil {
				return
			}
		case <-c.done:
			return
		case <-ctx.Done():
			return
		}
	}
}
