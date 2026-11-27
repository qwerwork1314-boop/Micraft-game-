import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var page = 0
    @State private var agreed = false

    var body: some View {
        ZStack {
            Brand.night.ignoresSafeArea()
            VStack(spacing: 24) {
                TabView(selection: $page) {
                    welcome.tag(0)
                    disclaimer.tag(1)
                    permissions.tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
            }
            .foregroundStyle(.white)
        }
        .animation(.easeInOut, value: page)
    }

    private var welcome: some View {
        VStack(spacing: 20) {
            Spacer()
            Image("Logo")
                .resizable().scaledToFit().frame(width: 120, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .shadow(color: Brand.emerald.opacity(0.5), radius: 30)
                .accessibilityHidden(true)
            Text("VitalFlow").font(.largeTitle.weight(.bold))
            Text("Understand your recovery, sleep and energy — privately, on your own devices.")
                .multilineTextAlignment(.center).font(.title3).opacity(0.85).padding(.horizontal, 32)
            Spacer()
            primaryButton("Continue") { page = 1 }
        }
        .padding(.bottom, 48)
    }

    private var disclaimer: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()
            Image(systemName: "stethoscope").font(.system(size: 44)).foregroundStyle(Brand.emerald)
            Text("Wellness, not medicine").font(.title.weight(.bold))
            Text("VitalFlow's scores are experimental wellness estimates based on your own data. They aren't clinically validated and can't diagnose or treat any condition. If you're worried about your health, talk to a professional.")
                .opacity(0.85)
            Toggle("I understand", isOn: $agreed).tint(Brand.emerald)
            Spacer()
            primaryButton("Continue") { page = 2 }.disabled(!agreed).opacity(agreed ? 1 : 0.5)
        }
        .padding(.horizontal, 28).padding(.bottom, 48)
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()
            Image(systemName: "heart.text.square.fill").font(.system(size: 44)).foregroundStyle(Brand.emerald)
            Text("Connect Apple Health").font(.title.weight(.bold))
            VStack(alignment: .leading, spacing: 10) {
                row("lock.shield", "Analysis runs on your iPhone and Apple Watch.")
                row("person.crop.circle.badge.xmark", "No account, no ads, no tracking.")
                row("slider.horizontal.3", "Choose exactly which data types to share.")
            }
            .opacity(0.9)
            Spacer()
            if model.healthAvailable {
                primaryButton("Connect Health") {
                    Task {
                        await model.requestHealthAccess()
                        model.settings.onboarded = true
                    }
                }
            }
            Button {
                model.setDemoMode(true)
                model.settings.onboarded = true
            } label: {
                Text("Explore with demo data").frame(maxWidth: .infinity).padding(.vertical, 12)
            }
            .foregroundStyle(.white.opacity(0.85))
        }
        .padding(.horizontal, 28).padding(.bottom, 48)
    }

    private func row(_ icon: String, _ text: LocalizedStringKey) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).frame(width: 26).foregroundStyle(Brand.emerald)
            Text(text)
        }
    }

    private func primaryButton(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Text(title).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 16)
                .background(Brand.flow, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .padding(.horizontal, 28)
        .buttonStyle(.plain)
    }
}
