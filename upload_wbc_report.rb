# G9 Sports WBC Report Uploader
baseball = Sport.find_by(slug: "baseball")
game = Game.find_or_create_by!(external_id: "wbc_20260308_kor_tpe") do |g|
  g.sport = baseball
  g.league = "wbc"
  g.league_name = "World Baseball Classic"
  g.home_team = "Taiwan"
  g.away_team = "South Korea"
  g.home_abbr = "TPE"
  g.away_abbr = "KOR"
  g.game_date = Time.zone.parse("2026-03-08 12:00:00 KST")
  g.venue = "Tokyo Dome"
  g.status = "scheduled"
end

report_content = <<~CONTENT
## 1. 전술적 매치업: "정교한 제구(Art) vs 파괴적 구위(Power)"

### 🇰🇷 대한민국: 류현진 (한화 이글스)
- **분석 지표**: 제구력 A+, 국제대회 경험 S, 완급 조절 S
- **승부 공식**: MLB 시절 장위청 상대 2타수 무안타 우위. 바깥쪽 체인지업과 몸쪽 커터 조합으로 대만 타자 타이밍 탈취.
- **변수**: 65구 제한에 따른 박영현-김택연 필승조 조기 투입 시점.

### 🇹🇼 대만: 구린루이양 (니혼햄 파이터스)
- **분석 지표**: 직구 구속 S (Max 157km/h), 수직 무브먼트 A, 디셉션 A+
- **승부 공식**: 수직 무브먼트가 뛰어난 하이 패스트볼. 50구 이후 구속 저하 발생.
- **공략 포인트**: 이정후, 김도영의 초반 커트 및 투구 수 늘리기 전략 필수.

## 2. 엔트리 및 게임 체인저
- **한국**: 셰이 위트컴(휴스턴), 저마이 존스(디트로이트) 등 빅리거 합류로 낯선 투수진 대응력 강화.
- **대만**: 린위민, 쉬뤄시 등 150km/h 이상 파이어볼러 대거 포진. 후반 불펜 싸움 주의.

## 3. 최종 결론
- **예상**: 대한민국 4 - 2 대만 (신승 예상)
- **핵심**: 류현진의 노련한 운영이 대만의 패기를 압도할 것.
CONTENT

Report.find_or_create_by!(game: game) do |r|
  r.title = "2026 WBC [대한민국 vs 대만] 딥 리서치 보고서"
  r.pick = "대한민국 승 (ML)"
  r.confidence = "★★★★☆"
  r.status = "published"
  r.published_at = Time.current
  r.content = report_content
end

puts "Successfully uploaded WBC report to G9 Sports Platform!"
