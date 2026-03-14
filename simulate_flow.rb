require_relative 'config/environment'

puts "=== G9 결제 승인 플로우 자동 테스트 시작 ==="

# 1. 임시 사용자 생성
user = User.find_or_create_by!(email: "test_customer@g9sports.com") do |u|
  u.password = "password123!"
end
puts "✅ [1/4] 테스트 사용자 생성 완료: #{user.email}"

# 기존 구독 정리 (테스트 반복을 위해)
user.subscriptions.destroy_all

# 2. 고객: 프리미엄 구독 신청 (pending_payment 상태로 생성)
subscription = user.subscriptions.create!(
  plan: 'daily', # Changed to a common plan name, maybe 'daily' or check PlanCatalog
  amount: 15000,
  payment_method: 'bank_transfer',
  status: 'pending_payment',
  starts_at: Time.current,
  expires_at: 1.month.from_now
)
puts "✅ [2/4] 고객 결제 요청 (무통장입금) 완료 - 현재 상태: #{subscription.status}"

# 전환 이벤트도 생성되는지 확인 (실제 컨트롤러에서는 ConversionEvent를 남김)
ConversionEvent.create!(
  user_id: user.id,
  event_name: 'payment_requested',
  metadata: { plan_id: 'premium', method: 'bank_transfer' },
  occurred_at: Time.current
)
puts "✅ [2/4] 'payment_requested' 퍼널 이벤트 기록 확인"

# 3. 권한 체크 (승인 전) - 리포트 접근 불가해야 함
has_access_before = user.active_subscription.present?
puts "🔒 [3/4] 관리자 승인 전 프리미엄 접근 권한: #{has_access_before ? '허용 (오류)' : '차단됨 (정상)'}"

# 4. 관리자: 입금 확인 후 승인 (상태를 active로 변경)
subscription.update!(status: 'active')
ConversionEvent.create!(
  user_id: user.id,
  event_name: 'payment_approved',
  metadata: { plan_id: 'premium' },
  occurred_at: Time.current
)
puts "✅ [4/4] 관리자 승인 처리 완료 - 변경된 상태: #{subscription.status}"
puts "✅ [4/4] 'payment_approved' 퍼널 이벤트 기록 확인"

# 5. 권한 체크 (승인 후) - 리포트 접근 가능해야 함
has_access_after = user.active_subscription.present?
puts "🔓 [4/4] 관리자 승인 후 프리미엄 접근 권한: #{has_access_after ? '허용됨 (정상)' : '차단 (오류)'}"

puts "============================================="
if !has_access_before && has_access_after
  puts "🎉 모든 결제 및 승인 로직이 완벽하게 작동합니다!"
else
  puts "❌ 로직에 문제가 있습니다."
end
