//
//  PermissionRequestView.swift
//  TextlinkEditor
//
//  앱 시작 시 필요한 권한을 요청하는 온보딩 뷰
//

import SwiftUI

struct PermissionRequestView: View {
    @Bindable var permissionManager: PermissionManager
    let onComplete: () -> Void

    @State private var currentPermissionIndex = 0

    private var pendingPermissions: [PermissionType] {
        PermissionType.allCases.filter { !permissionManager.isGranted($0) }
    }

    private var currentPermission: PermissionType? {
        guard currentPermissionIndex < pendingPermissions.count else { return nil }
        return pendingPermissions[currentPermissionIndex]
    }

    var body: some View {
        VStack(spacing: 32) {
            // 헤더
            VStack(spacing: 8) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 48))
                    .foregroundStyle(.accent)

                Text(L10n.get("permission.title"))
                    .font(.title)
                    .fontWeight(.bold)

                Text(L10n.get("permission.subtitle"))
                    .font(.subheadline)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Divider()
                .frame(width: 200)

            // 권한 목록
            VStack(spacing: 16) {
                ForEach(PermissionType.allCases) { permission in
                    PermissionRow(
                        permission: permission,
                        isGranted: permissionManager.isGranted(permission),
                        isCurrent: permission == currentPermission
                    )
                }
            }
            .frame(width: 400)

            Spacer()

            // 버튼
            VStack(spacing: 12) {
                if let permission = currentPermission {
                    Button {
                        requestCurrentPermission()
                    } label: {
                        Label(L10n.get("permission.grantAccess"), systemImage: "checkmark.shield")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Text(permission.description)
                        .font(.caption)
                        .foregroundStyle(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(width: 350)
                } else {
                    Button {
                        completeSetup()
                    } label: {
                        Label(L10n.get("permission.continue"), systemImage: "arrow.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }

                Button {
                    skipSetup()
                } label: {
                    Text(L10n.get("permission.skipForNow"))
                        .foregroundStyle(AppColors.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .frame(width: 250)
        }
        .padding(40)
        .frame(width: 500, height: 550)
        .background(ThemeAwareBackground(material: .contentBackground, blendingMode: .behindWindow))
    }

    private func requestCurrentPermission() {
        guard let permission = currentPermission else { return }

        if permissionManager.requestPermission(permission) {
            // 다음 권한으로 이동
            if currentPermissionIndex < pendingPermissions.count - 1 {
                currentPermissionIndex += 1
            }
        }
    }

    private func completeSetup() {
        permissionManager.completePermissionSetup()
        onComplete()
    }

    private func skipSetup() {
        permissionManager.completePermissionSetup()
        onComplete()
    }
}

// MARK: - Permission Row

struct PermissionRow: View {
    let permission: PermissionType
    let isGranted: Bool
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 16) {
            // 아이콘
            ZStack {
                Circle()
                    .fill(isGranted ? AppColors.savedIndicator.opacity(0.15) : (isCurrent ? Color.accent.opacity(0.15) : AppColors.controlBackground.opacity(0.5)))
                    .frame(width: 44, height: 44)

                Image(systemName: isGranted ? "checkmark" : permission.iconName)
                    .font(.system(size: 18))
                    .foregroundStyle(isGranted ? AppColors.savedIndicator : (isCurrent ? .accent : AppColors.textSecondary))
            }

            // 텍스트
            VStack(alignment: .leading, spacing: 2) {
                Text(permission.title)
                    .font(.headline)
                    .foregroundStyle(isGranted ? .secondary : .primary)

                Text(isGranted ? L10n.get("permission.granted") : L10n.get("permission.required"))
                    .font(.caption)
                    .foregroundStyle(isGranted ? AppColors.savedIndicator : AppColors.textSecondary)
            }

            Spacer()

            // 상태 표시
            if isGranted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AppColors.savedIndicator)
            } else if isCurrent {
                Image(systemName: "arrow.right.circle.fill")
                    .foregroundStyle(.accent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isCurrent && !isGranted ? Color.accent.opacity(0.05) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isCurrent && !isGranted ? Color.accent.opacity(0.3) : Color.clear, lineWidth: 1)
        )
    }
}

#Preview {
    PermissionRequestView(permissionManager: PermissionManager.shared) {
        print("Permission setup complete")
    }
}
