import SwiftUI
import Engine

@available(macOS 14.2, *)
public struct TodoListView: View {
    @State private var store = TodoStore.shared
    @State private var newTodoTitle = ""
    @FocusState private var isInputFocused: Bool
    
    // Toast state
    @State private var showCongratsToast = false
    @State private var congratsMessage = ""
    
    // Time config state
    @State private var showTimeConfig = false
    @State private var taskStart = Date()
    @State private var taskEnd = Date().addingTimeInterval(3600)
    @State private var newTodoErrorMessage = ""

    public init() {}

    private var sortedTasks: [TodoItem] {
        store.todaysTasks.sorted { (a, b) -> Bool in
            if a.isDone != b.isDone {
                return !a.isDone // Incomplete tasks at the top
            }
            
            if !a.isDone {
                let schedA = store.effectiveScheduleToday(a)
                let schedB = store.effectiveScheduleToday(b)
                
                switch (schedA, schedB) {
                case (let sA?, let sB?):
                    return sA.start < sB.start
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    return a.createdAt > b.createdAt
                }
            } else {
                return a.createdAt > b.createdAt
            }
        }
    }

    private func defaultScheduleTimes() -> (start: Date, end: Date) {
        let scheduledToday = store.todaysTasks.compactMap { store.effectiveScheduleToday($0) }
        if let maxEnd = scheduledToday.map({ $0.end }).max(), maxEnd > Date() {
            return (start: maxEnd, end: maxEnd.addingTimeInterval(3600))
        } else {
            return (start: Date(), end: Date().addingTimeInterval(3600))
        }
    }

    public var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                // Header
                HStack(alignment: .firstTextBaseline) {
                    Text("📝 Hôm nay")
                        .font(DSFont.wordmark)
                        .foregroundStyle(DS.textPrimary)
                    Spacer()
                    
                    let completed = store.todaysTasks.filter { $0.isDone }.count
                    let total = store.todaysTasks.count
                    Text("\(completed)/\(total) hoàn thành")
                        .font(DSFont.caption)
                        .foregroundStyle(DS.textSecondary)
                }
                .padding(.horizontal, DS.l)
                .padding(.top, DS.m + 5)
                .padding(.bottom, DS.s)
                .background(DS.surface)
                
                let ratio = store.todaysTasks.isEmpty ? 0.0 : Double(store.todaysTasks.filter { $0.isDone }.count) / Double(store.todaysTasks.count)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(DS.bg)
                        Rectangle()
                            .fill(DS.playing)
                            .frame(width: geo.size.width * ratio)
                            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: ratio)
                    }
                }
                .frame(height: 3)

                // Scrollable list
                ScrollView {
                    if sortedTasks.isEmpty {
                        VStack(spacing: DS.s) {
                            Image(systemName: "checklist.checked")
                                .font(.system(size: 24))
                                .foregroundStyle(DS.textTertiary)
                            Text("Chưa có việc nào\nthêm việc cho hôm nay nhé!")
                                .font(DSFont.caption)
                                .foregroundStyle(DS.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.vertical, 40)
                        .frame(maxWidth: .infinity)
                    } else {
                        VStack(spacing: DS.m) {
                            ForEach(sortedTasks) { item in
                                TodoRowView(
                                    item: item,
                                    onToggle: {
                                        if !item.isDone {
                                            showCongratsBanner(for: item.title)
                                        }
                                        store.toggleDone(id: item.id)
                                    },
                                    onToggleBlocked: { store.toggleBlocked(id: item.id) },
                                    onDelete: { store.deleteTask(id: item.id) },
                                    onCommitEdit: { newTitle in
                                        store.editTask(id: item.id, title: newTitle)
                                    },
                                    onSetSchedule: { start, end in
                                        store.setSchedule(id: item.id, start: start, end: end)
                                    },
                                    onClearSchedule: {
                                        store.clearSchedule(id: item.id)
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, DS.m)
                        .padding(.vertical, DS.m)
                    }
                }
                .background(DS.bg)

                Rectangle().fill(DS.stroke).frame(height: DS.borderWidth)

                // Input & Config panel area at bottom
                VStack(spacing: DS.m) {
                    // Cohesive container wrapping task name TextField, clock toggle button, and Add button
                    HStack(spacing: DS.s) {
                        TextField("Thêm việc mới...", text: $newTodoTitle)
                            .textFieldStyle(.plain)
                            .font(DSFont.control)
                            .foregroundStyle(DS.textPrimary)
                            .focused($isInputFocused)
                            .onSubmit {
                                commitNewTask()
                            }
                            .onKeyPress(.escape) {
                                newTodoTitle = ""
                                isInputFocused = false
                                return .handled
                            }

                        Button(action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                showTimeConfig.toggle()
                            }
                        }) {
                            Image(systemName: showTimeConfig ? "clock.fill" : "clock")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(showTimeConfig ? DS.accent : DS.textSecondary)
                                .padding(6)
                                .background(showTimeConfig ? DS.surfaceHi : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Toggle time configuration")

                        Button(action: commitNewTask) {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .black))
                                .foregroundStyle(DS.surface)
                                .padding(6)
                                .background(DS.accentPink)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Add task")
                    }
                    .padding(.horizontal, DS.m)
                    .padding(.vertical, DS.s)
                    .background(DS.surface)
                    .clipShape(RoundedRectangle(cornerRadius: DS.radiusS))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.radiusS)
                            .strokeBorder(DS.stroke, lineWidth: 1)
                    )

                    // Time Picker Config Panel
                    if showTimeConfig || isInputFocused {
                        VStack(spacing: DS.s) {
                            HStack {
                                Text("Bắt đầu:")
                                    .font(DSFont.control)
                                    .foregroundStyle(DS.textSecondary)
                                DatePicker("", selection: $taskStart, displayedComponents: .hourAndMinute)
                                    .datePickerStyle(.compact)
                                    .labelsHidden()
                                    .accessibilityLabel("Start time picker")
                                
                                Spacer()
                                
                                Text("Kết thúc:")
                                    .font(DSFont.control)
                                    .foregroundStyle(DS.textSecondary)
                                DatePicker("", selection: $taskEnd, displayedComponents: .hourAndMinute)
                                    .datePickerStyle(.compact)
                                    .labelsHidden()
                                    .accessibilityLabel("End time picker")
                            }
                            
                            HStack(spacing: DS.s) {
                                Text("Nhanh:")
                                    .font(DSFont.caption)
                                    .foregroundStyle(DS.textSecondary)
                                
                                ForEach([("+30m", 30.0), ("+1h", 60.0), ("+2h", 120.0)], id: \.0) { label, minutes in
                                    Button(action: {
                                        withAnimation {
                                            taskEnd = taskStart.addingTimeInterval(minutes * 60)
                                            showTimeConfig = true
                                        }
                                    }) {
                                        Text(label)
                                            .font(DSFont.caption)
                                            .foregroundStyle(DS.textPrimary)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(DS.surfaceHi)
                                            .clipShape(RoundedRectangle(cornerRadius: 6))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .strokeBorder(DS.stroke, lineWidth: 1)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                                Spacer()
                            }
                        }
                        .padding(DS.m)
                        .background(DS.surface)
                        .clipShape(RoundedRectangle(cornerRadius: DS.radiusS))
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.radiusS)
                                .strokeBorder(DS.stroke, lineWidth: 1)
                        )
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .top)),
                            removal: .opacity.combined(with: .move(edge: .top))
                        ))
                    }

                    if !newTodoErrorMessage.isEmpty {
                        Text(newTodoErrorMessage)
                            .font(DSFont.caption)
                            .foregroundStyle(DS.danger)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .transition(.opacity)
                    }
                }
                .padding(.horizontal, DS.m)
                .padding(.vertical, DS.s)
                .background(DS.surface)
                .onChange(of: isInputFocused) { _, newValue in
                    if newValue && newTodoTitle.isEmpty {
                        let times = defaultScheduleTimes()
                        taskStart = times.start
                        taskEnd = times.end
                    }
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        // Smoothly expand/collapse
                    }
                }
                .onChange(of: showTimeConfig) { _, newValue in
                    if newValue {
                        let times = defaultScheduleTimes()
                        taskStart = times.start
                        taskEnd = times.end
                        newTodoErrorMessage = ""
                    }
                }
                .onChange(of: taskStart) { _, _ in
                    showTimeConfig = true
                }
                .onChange(of: taskEnd) { _, _ in
                    showTimeConfig = true
                }
            }
            .onAppear {
                let times = defaultScheduleTimes()
                taskStart = times.start
                taskEnd = times.end
            }
            
            if showCongratsToast {
                Text(congratsMessage)
                    .font(DSFont.caption)
                    .foregroundStyle(DS.stroke)
                    .padding(.horizontal, DS.m)
                    .padding(.vertical, DS.s - 2)
                    .background(DS.accent)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder(DS.stroke, lineWidth: DS.borderWidth)
                    )
                    .cartoonShadow(radius: 4)
                    .padding(.top, 50)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(1)
            }
        }
    }

    private func commitNewTask() {
        let trimmed = newTodoTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        print("TodoListView: commitNewTask called with '\(trimmed)'")
        guard !trimmed.isEmpty else {
            print("TodoListView: commitNewTask skipped because trimmed title is empty")
            return
        }
        
        newTodoErrorMessage = ""
        
        if showTimeConfig {
            let calendar = Calendar.current
            let today = store.todayAnchor
            
            let startComponents = calendar.dateComponents([.hour, .minute], from: taskStart)
            let endComponents = calendar.dateComponents([.hour, .minute], from: taskEnd)
            
            guard let finalStart = calendar.date(bySettingHour: startComponents.hour ?? 0, minute: startComponents.minute ?? 0, second: 0, of: today),
                  let finalEnd = calendar.date(bySettingHour: endComponents.hour ?? 0, minute: endComponents.minute ?? 0, second: 0, of: today) else {
                newTodoErrorMessage = "Lỗi ngày"
                return
            }
            
            if finalEnd <= finalStart {
                newTodoErrorMessage = "Giờ kết thúc phải sau giờ bắt đầu"
                return
            }
            
            store.addTask(title: trimmed, start: finalStart, end: finalEnd)
        } else {
            store.addTask(title: trimmed)
        }
        
        newTodoTitle = ""
        isInputFocused = false
        showTimeConfig = false
    }

    private func showCongratsBanner(for title: String) {
        let congratsPhrases = [
            "Xuất sắc!",
            "Tuyệt vời!",
            "Đỉnh cao!",
            "Quá đỉnh!",
            "Tuyệt cú mèo!",
            "Yay! Xong rồi!"
        ]
        let randomPhrase = congratsPhrases.randomElement() ?? "Tuyệt vời!"
        congratsMessage = "\(randomPhrase) Đã hoàn thành: \(title) 🎉"
        
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            showCongratsToast = true
        }
        
        // Auto-dismiss after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeOut(duration: 0.3)) {
                showCongratsToast = false
            }
        }
    }
}

@available(macOS 14.2, *)
struct TodoRowView: View {
    let item: TodoItem
    let onToggle: () -> Void
    let onToggleBlocked: () -> Void
    let onDelete: () -> Void
    let onCommitEdit: (String) -> Void
    let onSetSchedule: (Date, Date) -> Void
    let onClearSchedule: () -> Void

    @State private var isEditing = false
    @State private var editTitle = ""
    @State private var isHovered = false
    @FocusState private var isTextfieldFocused: Bool

    // Schedule picker popover states
    @State private var showSchedulePicker = false
    @State private var scheduleStart = Date()
    @State private var scheduleEnd = Date().addingTimeInterval(3600)
    @State private var errorMessage = ""

    var body: some View {
        HStack(spacing: DS.s) {
            // Checkmark button
            Button(action: onToggle) {
                ZStack {
                    Circle()
                        .strokeBorder(item.isDone ? DS.playing : (item.status == .blocked ? DS.danger : DS.textSecondary), lineWidth: 2)
                        .background(
                            Circle()
                                .fill(item.isDone ? DS.playing : (item.status == .blocked ? DS.danger.opacity(0.15) : Color.clear))
                        )
                        .frame(width: 16, height: 16)
                    
                    if item.isDone {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .black))
                            .foregroundStyle(DS.surface)
                    } else if item.status == .blocked {
                        Image(systemName: "multiply")
                            .font(.system(size: 8, weight: .black))
                            .foregroundStyle(DS.danger)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.isDone ? "Uncheck task" : "Check task")

            if isEditing {
                TextField("Sửa việc...", text: $editTitle)
                    .textFieldStyle(.plain)
                    .font(DSFont.rowTitle)
                    .foregroundStyle(DS.textPrimary)
                    .focused($isTextfieldFocused)
                    .onSubmit {
                        commitEdit()
                    }
                    .onKeyPress(.escape) {
                        isEditing = false
                        return .handled
                    }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(DSFont.rowTitle)
                        .foregroundStyle(item.isDone ? DS.textTertiary : (item.status == .blocked ? DS.danger : DS.textPrimary))
                        .strikethrough(item.isDone, color: DS.textTertiary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    
                    if let schedule = TodoStore.shared.effectiveScheduleToday(item) {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.system(size: 9, weight: .bold))
                            Text(schedule.formattedTimeString)
                                .font(DSFont.caption)
                        }
                        .foregroundStyle(item.status == .blocked ? DS.danger : DS.accentPink)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(item.status == .blocked ? DS.danger.opacity(0.12) : DS.accentPink.opacity(0.12))
                        .clipShape(Capsule())
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .onTapGesture {
                    if !item.isDone {
                        editTitle = item.title
                        isEditing = true
                        isTextfieldFocused = true
                    }
                }
            }

            Spacer()

            HStack(spacing: DS.s) {
                if !item.isDone && !isEditing {
                    // Clock button always visible for active tasks
                    Button(action: {
                        if let s = TodoStore.shared.effectiveScheduleToday(item) {
                            scheduleStart = s.start
                            scheduleEnd = s.end
                        } else {
                            scheduleStart = Date()
                            scheduleEnd = Date().addingTimeInterval(3600)
                        }
                        errorMessage = ""
                        showSchedulePicker = true
                    }) {
                        Image(systemName: item.schedule != nil ? "clock.fill" : "clock")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(item.schedule != nil ? DS.accent : DS.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Set task schedule")
                    .popover(isPresented: $showSchedulePicker, arrowEdge: .trailing) {
                        VStack(spacing: DS.s) {
                            Text("Đặt thời gian")
                                .font(DSFont.control)
                                .foregroundStyle(DS.textPrimary)
                            
                            DatePicker("Bắt đầu", selection: $scheduleStart, displayedComponents: .hourAndMinute)
                                .datePickerStyle(.field)
                                .labelsHidden()
                                .accessibilityLabel("Start time picker")
                                
                            DatePicker("Kết thúc", selection: $scheduleEnd, displayedComponents: .hourAndMinute)
                                .datePickerStyle(.field)
                                .labelsHidden()
                                .accessibilityLabel("End time picker")
                                
                            // Quick-presets inside popover
                            HStack(spacing: DS.xs) {
                                ForEach([("+30m", 30.0), ("+1h", 60.0), ("+2h", 120.0)], id: \.0) { label, minutes in
                                    Button(label) {
                                        withAnimation {
                                            scheduleEnd = scheduleStart.addingTimeInterval(minutes * 60)
                                        }
                                    }
                                    .buttonStyle(.borderless)
                                    .controlSize(.mini)
                                }
                            }
                            
                            if !errorMessage.isEmpty {
                                Text(errorMessage)
                                    .font(DSFont.caption)
                                    .foregroundStyle(DS.danger)
                            }
                            
                            HStack(spacing: DS.s) {
                                Button("Xoá") {
                                    onClearSchedule()
                                    showSchedulePicker = false
                                }
                                .buttonStyle(.borderless)
                                .foregroundStyle(DS.danger)
                                
                                Spacer()
                                
                                Button("Huỷ") {
                                    showSchedulePicker = false
                                }
                                .buttonStyle(.borderless)
                                
                                Button("Lưu") {
                                    let calendar = Calendar.current
                                    let today = TodoStore.shared.todayAnchor
                                    
                                    let startComponents = calendar.dateComponents([.hour, .minute], from: scheduleStart)
                                    let endComponents = calendar.dateComponents([.hour, .minute], from: scheduleEnd)
                                    
                                    guard let finalStart = calendar.date(bySettingHour: startComponents.hour ?? 0, minute: startComponents.minute ?? 0, second: 0, of: today),
                                          let finalEnd = calendar.date(bySettingHour: endComponents.hour ?? 0, minute: endComponents.minute ?? 0, second: 0, of: today) else {
                                        errorMessage = "Lỗi ngày"
                                        return
                                    }
                                    
                                    if finalEnd <= finalStart {
                                        errorMessage = "Giờ kết thúc phải sau giờ bắt đầu"
                                        return
                                    }
                                    
                                    onSetSchedule(finalStart, finalEnd)
                                    showSchedulePicker = false
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(DS.accentPink)
                            }
                            .font(DSFont.caption)
                        }
                        .padding(DS.m)
                        .frame(width: 220)
                        .background(DS.surface)
                    }
                }

                if isHovered && !isEditing {
                    Button(action: onToggleBlocked) {
                        Image(systemName: item.status == .blocked ? "multiply.circle.fill" : "multiply.circle")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(DS.danger)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.status == .blocked ? "Unblock task" : "Block task")

                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(DS.danger)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Delete task")
                }
            }
        }
        .padding(.horizontal, DS.m)
        .padding(.vertical, DS.s)
        .background(
            RoundedRectangle(cornerRadius: DS.radiusS)
                .fill(isHovered ? DS.surfaceHi : DS.surface)
        )
        .padding(.horizontal, DS.s)
        .padding(.vertical, DS.xs)
        .onHover { hover in
            isHovered = hover
        }
    }

    private func commitEdit() {
        let trimmed = editTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            onCommitEdit(trimmed)
        }
        isEditing = false
    }
}
