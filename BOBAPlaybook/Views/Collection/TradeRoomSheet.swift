import SwiftUI

// MARK: - TradeRoomSheet
// Full-screen chat sheet for the BOBA Discord trade-room channel.
// States: (1) not authorized → Connect button, (2) authorized but not member → invite flow,
// (3) authorized + member → live channel.

struct TradeRoomSheet: View {
    @Bindable var discord: DiscordService
    @Environment(\.dismiss) private var dismiss

    @State private var inputText       = ""
    @State private var replyingTo: DiscordMessage? = nil
    @State private var showEmojiPicker = false
    @State private var emojiTargetId: String? = nil
    @State private var isAtBottom      = true
    @State private var loadingOlder    = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "313338").ignoresSafeArea()

                switch authState {
                case .notAuthorized:
                    connectView
                case .authorizedNotMember:
                    notMemberView
                case .authorizedMember:
                    channelView
                }
            }
            .navigationTitle("# trade-room")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color(hex: "1E1F22"), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if discord.isAuthorized, let user = discord.currentUser {
                        DiscordAvatar(user: user, size: 28)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
            }
        }
        .sheet(isPresented: $showEmojiPicker) {
            if let msgId = emojiTargetId {
                ReactionPickerView { emoji in
                    Task { await discord.addReaction(to: msgId, emoji: emoji) }
                    emojiTargetId  = nil
                    showEmojiPicker = false
                }
            }
        }
        .onAppear {
            Task {
                if discord.isAuthorized && !discord.memberChecked {
                    await discord.fetchCurrentUser()
                    await discord.checkMembership()
                }
                if discord.isMember && discord.messages.isEmpty {
                    await discord.loadInitialMessages()
                    discord.startPolling()
                    discord.markRead()
                }
            }
        }
        .onDisappear {
            discord.stopPolling()
            discord.markRead()
        }
    }

    // MARK: - Auth state helper

    private enum AuthState { case notAuthorized, authorizedNotMember, authorizedMember }
    private var authState: AuthState {
        if !discord.isAuthorized { return .notAuthorized }
        if discord.memberChecked && !discord.isMember { return .authorizedNotMember }
        return .authorizedMember
    }

    // MARK: - Connect view

    private var connectView: some View {
        VStack(spacing: 24) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 52))
                .foregroundStyle(Color(hex: "5865F2"))

            VStack(spacing: 8) {
                Text("BOBA Trade Room")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                Text("Connect your Discord account to chat\nwith the BOBA community.")
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }

            Button {
                Task { await discord.authorize() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "link")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Connect Discord")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: 280)
                .padding(.vertical, 14)
                .background(Color(hex: "5865F2"))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)

            if let err = discord.errorMessage {
                Text(err)
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: "F23F43"))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
        .padding(32)
    }

    // MARK: - Not-member view

    private var notMemberView: some View {
        VStack(spacing: 24) {
            Image(systemName: "person.badge.plus")
                .font(.system(size: 52))
                .foregroundStyle(Color(hex: "23A55A"))

            VStack(spacing: 8) {
                Text("Join the BOBA Discord")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                Text("You need to be a member of the\nBOBA Discord server to access the trade room.")
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }

            Link(destination: URL(string: "https://discord.gg/\(DiscordConfig.inviteCode)")!) {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Join Server")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: 280)
                .padding(.vertical, 14)
                .background(Color(hex: "23A55A"))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)

            Button {
                Task {
                    await discord.checkMembership()
                    if discord.isMember {
                        await discord.loadInitialMessages()
                        discord.startPolling()
                    }
                }
            } label: {
                Text("I've joined — check again")
                    .font(.system(size: 14))
                    .foregroundStyle(Color(hex: "5865F2"))
            }
            .buttonStyle(.plain)

            Button {
                discord.disconnect()
            } label: {
                Text("Use a different account")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.35))
            }
            .buttonStyle(.plain)
        }
        .padding(32)
    }

    // MARK: - Channel view

    private var channelView: some View {
        VStack(spacing: 0) {
            messageList
            Divider().overlay(Color.white.opacity(0.08))
            inputBar
        }
    }

    // MARK: - Message list

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    // Load-more trigger at the top
                    Group {
                        if discord.hasMoreHistory {
                            Button {
                                Task {
                                    guard !loadingOlder else { return }
                                    loadingOlder = true
                                    await discord.loadOlderMessages()
                                    loadingOlder = false
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    if loadingOlder {
                                        ProgressView()
                                            .progressViewStyle(.circular)
                                            .scaleEffect(0.7)
                                            .tint(.white)
                                    }
                                    Text(loadingOlder ? "Loading…" : "Load older messages")
                                        .font(.system(size: 13))
                                        .foregroundStyle(.white.opacity(0.45))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                            }
                            .buttonStyle(.plain)
                        } else {
                            VStack(spacing: 4) {
                                Image(systemName: "number")
                                    .font(.system(size: 24))
                                    .foregroundStyle(Color(hex: "5865F2"))
                                Text("Welcome to #trade-room")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(.white)
                                Text("This is the beginning of the channel.")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.white.opacity(0.45))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                        }
                    }

                    // Messages
                    ForEach(Array(discord.messages.enumerated()), id: \.element.id) { idx, msg in
                        let prev = idx > 0 ? discord.messages[idx - 1] : nil
                        let compact = isCompact(msg, prev: prev)

                        DiscordMessageRow(
                            message: msg,
                            isCompact: compact,
                            currentUserId: discord.currentUser?.id,
                            onReact: { emoji in
                                if emoji == "picker" {
                                    emojiTargetId  = msg.id
                                    showEmojiPicker = true
                                } else {
                                    Task { await discord.addReaction(to: msg.id, emoji: emoji) }
                                }
                            },
                            onRemoveReact: { emoji in
                                Task { await discord.removeReaction(from: msg.id, emoji: emoji) }
                            },
                            onReply: {
                                replyingTo   = msg
                                inputFocused = true
                            }
                        )
                        .id(msg.id)
                    }

                    // Invisible anchor for scroll-to-bottom
                    Color.clear.frame(height: 1).id("bottom")
                }
            }
            .onChange(of: discord.messages.count) { _, _ in
                if isAtBottom {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
            .onAppear {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
        }
    }

    // MARK: - Input bar

    private var inputBar: some View {
        VStack(spacing: 0) {
            // Reply indicator
            if let reply = replyingTo {
                HStack(spacing: 8) {
                    Image(systemName: "arrowshape.turn.up.left.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(hex: "5865F2"))
                    Text("Replying to \(reply.author.displayName)")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer()
                    Button {
                        replyingTo = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color(hex: "5865F2").opacity(0.15))
            }

            HStack(alignment: .bottom, spacing: 10) {
                TextField("Message #trade-room", text: $inputText, axis: .vertical)
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                    .lineLimit(1...6)
                    .focused($inputFocused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(hex: "383A40"))
                    .clipShape(RoundedRectangle(cornerRadius: 22))

                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                         ? .white.opacity(0.2)
                                         : Color(hex: "5865F2"))
                        .frame(width: 38, height: 38)
                }
                .buttonStyle(.plain)
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(hex: "313338"))
        }
    }

    // MARK: - Helpers

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let replyId = replyingTo?.id
        inputText  = ""
        replyingTo = nil
        Task { await discord.send(text, replyTo: replyId) }
    }

    /// Same author within 7 minutes of previous message = compact display
    private func isCompact(_ msg: DiscordMessage, prev: DiscordMessage?) -> Bool {
        guard let prev else { return false }
        guard msg.author.id == prev.author.id else { return false }
        guard let d1 = msg.parsedDate, let d2 = prev.parsedDate else { return false }
        return abs(d1.timeIntervalSince(d2)) < 7 * 60
    }
}
