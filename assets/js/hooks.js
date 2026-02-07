let Hooks = {}

Hooks.Clipboard = {
    mounted() {
        this.handleEvent("copy-to-clipboard", ({ text: text }) => {
            navigator.clipboard.writeText(text).then(() => {
                this.pushEventTo(this.el, "copied-to-clipboard", { text: text })
                setTimeout(() => {
                    this.pushEventTo(this.el, "reset-copied", {})
                }, 2000)
            })
        })
    }
}

Hooks.ScrollToBottom = {
    mounted() {
        this.scrollToBottom()
    },
    updated() {
        this.scrollToBottom()
    },
    scrollToBottom() {
        this.el.scrollTop = this.el.scrollHeight
    }
}

Hooks.MentionInput = {
    mounted() {
        this.mentionStartPos = null
        this.mentions = []

        // Handle input events
        this.el.addEventListener('input', (e) => {
            const text = this.getTextContent()
            this.pushEvent('message_input_change', { value: text })
        })

        // Handle keydown for special keys
        this.el.addEventListener('keydown', (e) => {
            if (e.key === 'Enter' && !e.shiftKey) {
                e.preventDefault()
                this.submitMessage()
            }
            if (e.key === 'Escape') {
                this.pushEvent('close_mention_dropdown', {})
            }
        })

        // Listen for submit button click via custom event
        this.el.addEventListener('chat:submit', () => {
            this.submitMessage()
        })

        // Listen for mention insertion from server
        this.handleEvent('insert_mention', ({ id, name }) => {
            this.insertMentionChip(id, name)
        })

        // Listen for clear input
        this.handleEvent('clear_input', () => {
            this.el.innerHTML = ''
            this.mentions = []
        })
    },

    getTextContent() {
        // Get text content, replacing mention chips with @name
        let text = ''
        this.el.childNodes.forEach(node => {
            if (node.nodeType === Node.TEXT_NODE) {
                text += node.textContent
            } else if (node.classList && node.classList.contains('mention-chip')) {
                text += '@' + node.dataset.name
            }
        })
        return text
    },

    insertMentionChip(contactId, contactName) {
        const text = this.getTextContent()

        // Find the @query to replace (everything from last @ to cursor)
        const lastAtIndex = text.lastIndexOf('@')
        if (lastAtIndex === -1) return

        // Create the mention chip - keep in sync with chat_live.ex mention_chip_html/2
        const chip = document.createElement('span')
        chip.className = 'mention-chip inline-flex items-center gap-1 bg-slate-200 text-slate-700 px-1 py-px rounded-full text-xs font-medium mx-0.5'
        chip.contentEditable = 'false'
        chip.dataset.contactId = contactId
        chip.dataset.name = contactName
        const firstName = contactName.split(' ')[0] || contactName
        chip.innerHTML = `
            <span class="w-4 h-4 bg-slate-500 rounded-full flex items-center justify-center text-[10px] text-white font-medium">${contactName.charAt(0).toUpperCase()}</span>
            <span>${firstName}</span>
        `

        // Find and replace the @query text
        this.replaceAtQuery(chip)

        // Track the mention
        this.mentions.push({ id: contactId, name: contactName })

        // Move cursor after the chip
        this.placeCursorAfter(chip)

        // Notify server
        this.pushEvent('message_input_change', { value: this.getTextContent() })
    },

    replaceAtQuery(chip) {
        // Walk through nodes and find the @ text to replace
        const walker = document.createTreeWalker(this.el, NodeFilter.SHOW_TEXT)
        let node
        while (node = walker.nextNode()) {
            const atIndex = node.textContent.lastIndexOf('@')
            if (atIndex !== -1) {
                // Split the text node and insert the chip
                const before = node.textContent.substring(0, atIndex)

                const beforeNode = document.createTextNode(before)
                const afterNode = document.createTextNode(' ')

                const parent = node.parentNode
                parent.insertBefore(beforeNode, node)
                parent.insertBefore(chip, node)
                parent.insertBefore(afterNode, node)
                parent.removeChild(node)
                return
            }
        }
    },

    placeCursorAfter(element) {
        const range = document.createRange()
        const selection = window.getSelection()
        range.setStartAfter(element)
        range.collapse(true)
        selection.removeAllRanges()
        selection.addRange(range)
        this.el.focus()
    },

    submitMessage() {
        const text = this.getTextContent().trim()
        if (!text || this.mentions.length === 0) return

        this.pushEvent('send_message', {
            message: text,
            mentions: this.mentions
        })
    },

    getMentions() {
        return Array.from(this.el.querySelectorAll('.mention-chip')).map(chip => ({
            id: parseInt(chip.dataset.contactId),
            name: chip.dataset.name
        }))
    }
}

export default Hooks