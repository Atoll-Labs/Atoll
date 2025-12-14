//
//  NotchNotesView.swift
//  DynamicIsland
//
//  Created by Assistant
//

import SwiftUI
import Defaults

struct NotchNotesView: View {
    @FocusState private var isFocused: Bool
    @Default(.savedNotes) var savedNotes
    @Default(.clipboardDisplayMode) var clipboardDisplayMode
    @Default(.enableClipboardManager) var enableClipboardManager
    
    @State private var selectedNoteId: UUID?
    @State private var isEditingNewNote = false
    
    // Editor State
    @State private var editorTitle: String = ""
    @State private var editorContent: String = ""
    @State private var editorColorIndex: Int = 0
    @State private var editorNoteId: UUID?

    @Default(.enableNotes) var enableNotes
    
    var showSplitView: Bool {
        return enableClipboardManager && clipboardDisplayMode == .separateTab
    }

    var body: some View {
        HStack(spacing: 0) {
            if showSplitView {
                NotchClipboardList()
                    .frame(maxWidth: .infinity)
                
                if enableNotes {
                    Divider()
                        .background(Color.white.opacity(0.15))
                }
            }
            
            if enableNotes {
                ZStack {
                    if isEditingNewNote || selectedNoteId != nil {
                        NoteEditorView(
                            title: $editorTitle,
                            content: $editorContent,
                            colorIndex: $editorColorIndex,
                            onSave: saveNote,
                            onCancel: cancelEdit,
                            isNew: isEditingNewNote
                        )
                        .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .trailing)))
                    } else {
                        NoteListView(
                            notes: savedNotes,
                            onSelect: selectNote,
                            onCreate: createNote,
                            onDelete: deleteNote,
                            onDeleteItem: deleteNoteItem,
                            onClearAll: clearAllNotes
                        )
                        .transition(.asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .leading)))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped() // Prevent overflow during transition
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isEditingNewNote)
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: selectedNoteId)
            }
        }
    }
    
    // MARK: - Actions
    
    private func createNote() {
        editorTitle = ""
        editorContent = ""
        editorColorIndex = 0 // Default Yellow
        editorNoteId = UUID()
        isEditingNewNote = true
    }
    
    private func selectNote(_ note: NoteItem) {
        editorTitle = note.title
        editorContent = note.content
        editorColorIndex = note.colorIndex
        editorNoteId = note.id
        selectedNoteId = note.id
        isEditingNewNote = false
    }
    
    private func saveNote() {
        if let id = editorNoteId {
            let newNote = NoteItem(
                id: id,
                title: editorTitle.isEmpty ? "Untitled Note" : editorTitle,
                content: editorContent,
                creationDate: Date(),
                colorIndex: editorColorIndex
            )
            
            var notes = savedNotes
            if let index = notes.firstIndex(where: { $0.id == id }) {
                notes[index] = newNote
            } else {
                notes.insert(newNote, at: 0)
            }
            savedNotes = notes
        }
        
        closeEditor()
    }
    
    private func deleteNote(_ indexSet: IndexSet) {
        var notes = savedNotes
        notes.remove(atOffsets: indexSet)
        savedNotes = notes
    }
    
    private func deleteNoteItem(_ note: NoteItem) {
        var notes = savedNotes
        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            notes.remove(at: index)
            savedNotes = notes
        }
    }
    
    private func clearAllNotes() {
        savedNotes.removeAll()
    }

    private func cancelEdit() {
        closeEditor()
    }
    
    private func closeEditor() {
        isEditingNewNote = false
        selectedNoteId = nil
        // Tiny delay to clear state after animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            editorTitle = ""
            editorContent = ""
        }
    }
}

// MARK: - Subviews

struct NotchClipboardList: View {
    @ObservedObject var clipboardManager = ClipboardManager.shared
    @State private var hoveredItemId: UUID?
    @State private var justCopiedId: UUID?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Clipboard")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                
                Spacer()
                
                if !clipboardManager.clipboardHistory.isEmpty {
                    Button(action: { clipboardManager.clearHistory() }) {
                        Image(systemName: "trash")
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.6))
                            .padding(6)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 12)
            
            if clipboardManager.clipboardHistory.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary.opacity(0.3))
                    Text("No copies yet")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("Copy text to see it here")
                        .font(.caption)
                        .foregroundStyle(.secondary.opacity(0.7))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .offset(y: -20)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) { // Tighter spacing
                        ForEach(clipboardManager.clipboardHistory) { item in
                            NotchClipboardItemRow(
                                item: item,
                                isHovered: hoveredItemId == item.id,
                                justCopied: justCopiedId == item.id
                            )
                            .contentShape(Rectangle())
                            .onHover { isHovered in
                                hoveredItemId = isHovered ? item.id : nil
                            }
                            .onTapGesture {
                                clipboardManager.copyToClipboard(item)
                                withAnimation {
                                    justCopiedId = item.id
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    if justCopiedId == item.id {
                                        withAnimation {
                                            justCopiedId = nil
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                }
            }
        }
    }
}

struct NotchClipboardItemRow: View {
    let item: ClipboardItem
    let isHovered: Bool
    let justCopied: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: justCopied ? "checkmark.circle.fill" : item.type.icon)
                .font(.system(size: 14))
                .foregroundColor(justCopied ? .green : .blue)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(item.preview)
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                
                HStack {
                    Text(item.type.displayName)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(timeAgoString(from: item.timestamp))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(isHovered ? 0.3 : 0.15))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    private func timeAgoString(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "Just now" }
        if interval < 3600 { return "\(Int(interval/60))m" }
        return "\(Int(interval/3600))h"
    }
}


struct NoteListView: View {
    let notes: [NoteItem]
    let onSelect: (NoteItem) -> Void
    let onCreate: () -> Void
    let onDelete: (IndexSet) -> Void // Keep for swipe support
    let onDeleteItem: (NoteItem) -> Void // New for button support
    let onClearAll: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Notes")
                    .font(.system(size: 18, weight: .semibold, design: .rounded)) // Slightly smaller, cleaner
                    .foregroundStyle(.white)
                
                Spacer()
                
                if !notes.isEmpty {
                    Button(action: onClearAll) {
                        Image(systemName: "trash")
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.6))
                            .padding(6)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                Button(action: onCreate) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold)) // Reduced size to match trash
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 20)
            .padding(.top, 12) // Reduced padding to move header higher
            .padding(.bottom, 12)
            
            if notes.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "note.text")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary.opacity(0.3))
                    Text("No notes yet")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("Click + to create a note")
                        .font(.caption)
                        .foregroundStyle(.secondary.opacity(0.7))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .offset(y: -20) // Visually center slightly upwards
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) { // Matched tighter spacing
                        ForEach(notes) { note in
                            NoteRow(note: note, onDelete: { onDeleteItem(note) })
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    onSelect(note)
                                }
                        }
                    }
                    .padding(.horizontal, 16) // Matched padding
                    .padding(.bottom, 20)
                }
            }
        }
    }
}

struct NoteRow: View {
    let note: NoteItem
    let onDelete: () -> Void
    @State private var isHovered = false
    @State private var isCopied = false
    
    var body: some View {
        HStack(spacing: 12) { // Matched spacing
            // Color Indicator
            RoundedRectangle(cornerRadius: 3)
                .fill(note.color)
                .frame(width: 4)
                .padding(.vertical, 2)
            
            VStack(alignment: .leading, spacing: 4) { // Matched spacing
                Text(note.title)
                    .font(.system(size: 13, weight: .medium, design: .rounded)) // Matched size
                    .foregroundStyle(.white)
                    .lineLimit(1)
                
                Text(note.content.isEmpty ? "No content" : note.content)
                    .font(.system(size: 11)) // Slightly smaller for secondary text
                    .foregroundStyle(.secondary)
                    .lineLimit(1) // Single line description like clipboard
                    .multilineTextAlignment(.leading)
            }
            
            Spacer()
            
            if isHovered {
                HStack(spacing: 4) {
                    Button(action: {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(note.content, forType: .string)
                        
                        withAnimation {
                            isCopied = true
                        }
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation {
                                isCopied = false
                            }
                        }
                    }) {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 12)) // Matched icon size
                            .foregroundStyle(isCopied ? .green : .white.opacity(0.8))
                            .padding(6)
                    }
                    .buttonStyle(PlainButtonStyle())

                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 12)) // Matched icon size
                            .foregroundStyle(.red.opacity(0.8))
                            .padding(6)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .transition(.opacity.animation(.easeInOut(duration: 0.2)))
            } else {
                Text(note.creationDate.formatted(.dateTime.day().month()))
                    .font(.system(size: 10)) // Matched timestamp size
                    .foregroundStyle(.secondary.opacity(0.5))
            }
        }
        .padding(10) // Matched padding
        .background(Color(nsColor: .controlBackgroundColor).opacity(isHovered ? 0.5 : 0.3))
        .clipShape(RoundedRectangle(cornerRadius: 8)) // Matched corner radius
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
}

struct NoteEditorView: View {
    @Binding var title: String
    @Binding var content: String
    @Binding var colorIndex: Int
    let onSave: () -> Void
    let cancelAction: () -> Void
    let isNew: Bool
    
    init(title: Binding<String>, content: Binding<String>, colorIndex: Binding<Int>, onSave: @escaping () -> Void, onCancel: @escaping () -> Void, isNew: Bool) {
        self._title = title
        self._content = content
        self._colorIndex = colorIndex
        self.onSave = onSave
        self.cancelAction = onCancel
        self.isNew = isNew
    }

    @FocusState private var isContentFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Button(action: cancelAction) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Notes")
                    }
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
                }
                .buttonStyle(PlainButtonStyle())
                
                Spacer()
                
                Button(action: onSave) {
                    Text("Done")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(NoteItem.colors[colorIndex])
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(16)
            
            // Title & Color Picker Row
            HStack(alignment: .center, spacing: 12) {
                TextField("Title", text: $title)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .textFieldStyle(.plain)
                
                Spacer() // Push colors to the right
                
                // Color Picker
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(0..<NoteItem.colors.count, id: \.self) { index in
                            Circle()
                                .fill(NoteItem.colors[index])
                                .frame(width: 16, height: 16)
                                .overlay(
                                    Circle()
                                        .stroke(Color.white, lineWidth: colorIndex == index ? 2 : 0)
                                        .padding(-2)
                                )
                                .onTapGesture {
                                    withAnimation {
                                        colorIndex = index
                                    }
                                }
                        }
                    }
                    .padding(.vertical, 4) // Prevent vertical selection ring clipping
                    .padding(.horizontal, 4) // Prevent horizontal selection ring clipping
                }
                .frame(maxWidth: 160) // Limit width so title gets space
            }
            .padding(.leading, 16)
            .padding(.trailing, 4) // Reduced trailing padding to move circles right
            .padding(.bottom, 8)
            
            Divider()
                .background(Color.white.opacity(0.1))
            
            // Content Input
            ZStack(alignment: .topLeading) {
                if content.isEmpty { // Placeholder
                    Text("Start typing...")
                        .font(.system(size: 13, design: .rounded)) // Reduced from 14
                        .foregroundStyle(.secondary.opacity(0.5))
                        .padding(.top, 10)
                        .padding(.leading, 12)
                        .allowsHitTesting(false)
                }
                
                TextEditor(text: $content)
                    .font(.system(size: 13, design: .rounded)) // Reduced from 14
                    .foregroundStyle(.white)
                    .lineSpacing(4)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .focused($isContentFocused)
                    .frame(maxHeight: .infinity)
                    .background(Color.white.opacity(0.05))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity) // Ensure VStack takes full space
        .background(Color.black) // Ensure solid background
        .onAppear {
            if isNew {
                isContentFocused = true
            }
        }
    }
}
