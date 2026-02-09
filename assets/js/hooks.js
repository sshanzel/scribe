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
        this.selectedIndex = -1

        this.el.addEventListener('input', (e) => {
            const text = this.getTextContent()
            this.pushEvent('message_input_change', { value: text })
        })

        this.el.addEventListener('keydown', (e) => {
            const dropdown = document.querySelector('[data-mention-dropdown]')
            const items = dropdown ? dropdown.querySelectorAll('[data-contact-option]') : []

            if (dropdown && items.length > 0) {
                if (e.key === 'ArrowDown') {
                    e.preventDefault()
                    this.selectedIndex = Math.min(this.selectedIndex + 1, items.length - 1)
                    this.updateSelectedVisual(items)
                    return
                }
                if (e.key === 'ArrowUp') {
                    e.preventDefault()
                    this.selectedIndex = Math.max(this.selectedIndex - 1, 0)
                    this.updateSelectedVisual(items)
                    return
                }
                if ((e.key === 'Enter' || e.key === 'Tab') && this.selectedIndex >= 0) {
                    e.preventDefault()
                    const selectedItem = items[this.selectedIndex]
                    if (selectedItem) {
                        const contactId = selectedItem.dataset.contactId
                        this.pushEvent('select_contact', { id: contactId })
                        this.resetSelectedIndex()
                    }
                    return
                }
            }

            if (e.key === 'Enter' && !e.shiftKey) {
                e.preventDefault()
                this.submitMessage()
            }
            if (e.key === 'Escape') {
                this.resetSelectedIndex()
                this.pushEvent('close_mention_dropdown', {})
            }
        })

        this.el.addEventListener('paste', (e) => {
            e.preventDefault()
            const text = e.clipboardData.getData('text/plain')
            if (text) {
                const selection = window.getSelection()
                if (selection.rangeCount > 0) {
                    const range = selection.getRangeAt(0)
                    range.deleteContents()
                    const textNode = document.createTextNode(text)
                    range.insertNode(textNode)
                    range.setStartAfter(textNode)
                    range.setEndAfter(textNode)
                    selection.removeAllRanges()
                    selection.addRange(range)
                } else {
                    document.execCommand('insertText', false, text)
                }
                this.pushEvent('message_input_change', { value: this.getTextContent() })
            }
        })

        this.handleEvent('contact_results_changed', () => {
            this.resetSelectedIndex()
        })

        this.el.addEventListener('chat:submit', () => {
            this.submitMessage()
        })

        this.handleEvent('insert_mention', ({ id, name, source }) => {
            this.insertMentionChip(id, name, source)
        })

        this.handleEvent('clear_input', () => {
            this.el.innerHTML = ''
            this.mentions = []
            this.el.focus()
        })
    },

    getTextContent() {
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

    insertMentionChip(contactId, contactName, source) {
        const text = this.getTextContent()

        const lastAtIndex = text.lastIndexOf('@')
        if (lastAtIndex === -1) return

        // Get logo path based on source
        const logoPath = this.getSourceLogoPath(source)

        // Create the mention chip - keep in sync with chat_live.ex mention_chip_html/3
        // Use DOM APIs to prevent XSS from contact names
        const chip = document.createElement('span')
        chip.className = 'mention-chip inline-flex items-center gap-1 bg-slate-200 text-slate-700 px-1 py-px rounded-full text-xs font-medium mx-0.5'
        chip.contentEditable = 'false'
        chip.dataset.contactId = contactId
        chip.dataset.name = contactName
        chip.dataset.source = source || 'local'
        const firstName = contactName.split(' ')[0] || contactName

        // Build chip structure safely using DOM APIs
        const relativeSpan = document.createElement('span')
        relativeSpan.className = 'relative'

        const initialSpan = document.createElement('span')
        initialSpan.className = 'w-4 h-4 bg-slate-500 rounded-full flex items-center justify-center text-[10px] text-white font-medium'
        initialSpan.textContent = contactName.charAt(0).toUpperCase()

        const logoImg = document.createElement('img')
        logoImg.src = logoPath
        logoImg.className = 'absolute -bottom-0.5 -right-1 w-2.5 h-2.5 bg-[#f0f5f5] rounded-full p-px border-0'

        relativeSpan.appendChild(initialSpan)
        relativeSpan.appendChild(logoImg)

        const nameSpan = document.createElement('span')
        nameSpan.textContent = firstName

        chip.appendChild(relativeSpan)
        chip.appendChild(nameSpan)

        this.replaceAtQuery(chip)
        this.mentions.push({ id: contactId, name: contactName, source: source })
        this.placeCursorAfter(chip)
        this.pushEvent('message_input_change', { value: this.getTextContent() })
    },

    getSourceLogoPath(source) {
        switch (source) {
            case 'hubspot':
                return '/images/hubspot-logo.svg'
            case 'salesforce':
                return '/images/salesforce-logo.svg'
            default:
                return '/images/jump-logo.svg'
        }
    },

    replaceAtQuery(chip) {
        const walker = document.createTreeWalker(this.el, NodeFilter.SHOW_TEXT)
        let node
        while (node = walker.nextNode()) {
            const atIndex = node.textContent.lastIndexOf('@')
            if (atIndex !== -1) {
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
        if (!text) return

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
    },

    resetSelectedIndex() {
        this.selectedIndex = -1
        this.el.removeAttribute('aria-activedescendant')
    },

    updateSelectedVisual(items) {
        items.forEach((item, index) => {
            const isSelected = index === this.selectedIndex
            if (isSelected) {
                item.classList.add('bg-slate-100')
                item.setAttribute('aria-selected', 'true')
                if (!item.id) {
                    item.id = `mention-option-${index}`
                }
                this.el.setAttribute('aria-activedescendant', item.id)
                item.scrollIntoView({ block: 'nearest' })
            } else {
                item.classList.remove('bg-slate-100')
                item.setAttribute('aria-selected', 'false')
            }
        })

        if (this.selectedIndex < 0 || this.selectedIndex >= items.length) {
            this.el.removeAttribute('aria-activedescendant')
        }
    }
}

export default Hooks