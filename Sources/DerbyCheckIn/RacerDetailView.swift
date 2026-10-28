import DerbyCore
import DerbyKit
import SwiftUI

struct RacerDetailView: View {
    @EnvironmentObject var store: Store
    @Binding var racer: Racer
    @State private var cameraFor: PhotoKind?
    @State private var confirmDelete = false

    private var maxWeight: String { store.data.maxWeightOz.formatted() }

    var body: some View {
        Form {
            Section("Racer") {
                TextField("First name", text: $racer.firstName)
                TextField("Last name", text: $racer.lastName)
                Picker("Race group", selection: $racer.rank) {
                    Text("Choose…").tag("")
                    ForEach(store.data.groups) { Text($0.name).tag($0.rank) }
                    if !racer.rank.isEmpty && !store.data.groups.contains(where: { $0.rank == racer.rank }) {
                        Text(racer.groupName).tag(racer.rank)
                    }
                }
            }

            Section {
                LabeledContent("Car number") {
                    HStack {
                        TextField("Car number", value: $racer.carNumber, format: .number.grouping(.never))
                            .labelsHidden()
                            .frame(width: 100)
                        Button("Next Available") { racer.carNumber = store.data.nextCarNumber(for: racer) }
                            .disabled(racer.rank.isEmpty)
                            .help("Next free number in this group's series")
                    }
                }
                if let problem = store.data.carNumberProblem(for: racer) {
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                LabeledContent("Car name") {
                    HStack {
                        TextField("Car name", text: $racer.carName)
                            .labelsHidden()
                        Text("\(racer.carName.count)/\(maxCarNameLength)")
                            .monospacedDigit()
                            .foregroundStyle(racer.carName.count >= maxCarNameLength ? .orange : .secondary)
                    }
                }
                LabeledContent("Weight (oz)") {
                    HStack {
                        TextField("Weight", value: $racer.weightOz, format: .number.precision(.fractionLength(0...2)))
                            .labelsHidden()
                            .frame(width: 100)
                        if racer.weightOz > store.data.maxWeightOz {
                            Label("Over \(maxWeight) oz", systemImage: "xmark.circle.fill").foregroundStyle(.red)
                        } else if racer.weightOz > 0 {
                            Label("OK", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        }
                    }
                }
                Toggle("Exclude from racing", isOn: $racer.exclude)
            } header: {
                HStack {
                    Text("Car")
                    Spacer()
                    Button("Add Another Car for \(racer.firstName.isEmpty ? "This Racer" : racer.firstName)",
                           systemImage: "plus") { store.addCar(for: racer) }
                        .buttonStyle(.borderless)
                        .disabled(racer.fullName.isEmpty)
                }
            }

            Section("Inspection") {
                Toggle("Weight is \(maxWeight) oz or less", isOn: $racer.inspection.weightOK)
                Toggle("Length, width and height within limits", isOn: $racer.inspection.dimensionsOK)
                Toggle("Ground clearance OK", isOn: $racer.inspection.clearanceOK)
                Toggle("Wheels and axles meet the rules", isOn: $racer.inspection.wheelsAxlesOK)
                Toggle("No loose parts, liquids or springs", isOn: $racer.inspection.noLooseParts)
                Picker("Result", selection: $racer.inspection.passed) {
                    Text("Not inspected").tag(Bool?.none)
                    Text("Passed").tag(Bool?.some(true))
                    Text("Failed").tag(Bool?.some(false))
                }
                .pickerStyle(.segmented)
            }

            Section("Photos") {
                HStack(alignment: .top, spacing: 24) {
                    PhotoSlot(title: "Racer", icon: "person.crop.square", filename: racer.racerPhoto,
                              onCamera: { cameraFor = .racer },
                              onFile: { store.choosePhotoFile(kind: .racer, racerID: racer.id) },
                              onRemove: { store.setPhoto(nil, kind: .racer, racerID: racer.id) })
                    PhotoSlot(title: "Car", icon: "car.side", filename: racer.carPhoto,
                              onCamera: { cameraFor = .car },
                              onFile: { store.choosePhotoFile(kind: .car, racerID: racer.id) },
                              onRemove: { store.setPhoto(nil, kind: .car, racerID: racer.id) })
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }

            Section("Notes") {
                TextField("Notes", text: $racer.notes, axis: .vertical)
                    .labelsHidden()
                    .lineLimit(2...5)
            }

            Section {
                checkInRow
            }

            Section {
                Button("Delete Racer…", role: .destructive) { confirmDelete = true }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(racer.fullName.isEmpty ? "New Racer" : racer.fullName)
        .sheet(item: $cameraFor) { kind in
            CameraSheet(title: kind == .racer ? "Racer Photo" : "Car Photo") { image in
                store.setPhoto(image, kind: kind, racerID: racer.id)
            }
        }
        .confirmationDialog("Delete \(racer.fullName.isEmpty ? "this racer" : racer.fullName)?",
                            isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { store.deleteRacer(racer.id) }
        } message: {
            Text("Their details and photos will be removed.")
        }
    }

    @ViewBuilder private var checkInRow: some View {
        if let time = racer.checkedInAt {
            HStack {
                Label("Checked in at \(time.formatted(date: .omitted, time: .shortened))", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                    .font(.headline)
                Spacer()
                Button("Undo Check-In") { racer.checkedInAt = nil }
            }
        } else {
            let blocker = store.data.checkInBlocker(racer)
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    if let blocker {
                        Text(blocker).foregroundStyle(.secondary)
                    }
                    if racer.inspection.passed != true {
                        Label(racer.inspection.passed == false ? "Car failed inspection" : "Car not inspected yet",
                              systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
                Spacer()
                Button("Check In") { racer.checkedInAt = Date() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(blocker != nil)
            }
        }
    }
}

struct PhotoSlot: View {
    @EnvironmentObject var store: Store
    let title: String
    let icon: String
    let filename: String?
    let onCamera: () -> Void
    let onFile: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Rectangle().fill(.quaternary)
                if let filename, let image = NSImage(contentsOf: store.photoURL(filename)) {
                    Image(nsImage: image).resizable().scaledToFill()
                } else {
                    Image(systemName: icon).font(.system(size: 40)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 220, height: 165)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(title).font(.headline)
            HStack {
                Button("Camera", systemImage: "camera", action: onCamera)
                Button("File…", action: onFile)
                if filename != nil {
                    Button("Remove", role: .destructive, action: onRemove)
                }
            }
        }
    }
}
