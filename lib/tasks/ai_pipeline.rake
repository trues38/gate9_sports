namespace :ai do
  desc "AI 파이프라인 결과물(JSON 스냅샷)을 읽어 실전 DB에 Game과 Report를 생성합니다."
  task ingest_reports: :environment do
    puts "🤖 G9 Intelligence: 실전 데이터 인입 시작..."
    
    snapshot_dir = "/Users/js/Documents/project/G9_Sports_Final/engine/data_lake/snapshots"
    processed_dir = File.join(snapshot_dir, "processed")
    Dir.mkdir(processed_dir) unless Dir.exist?(processed_dir)

    files = Dir.glob("#{snapshot_dir}/*.json")
    if files.empty?
      puts "📭 처리할 신규 스냅샷이 없습니다."
      next
    end

    files.each do |file|
      begin
        data = JSON.parse(File.read(file))
        meta = data["meta"]
        outputs = data["intermediate_outputs"]["extracted_stats"]
        
        game_info = outputs["game_info"]
        report_text = outputs["report"]
        reasoning = outputs["reasoning"]

        # 1. Sport 찾기
        sport_slug = meta["match_id"].split('_').first || "basketball"
        sport = Sport.find_by(slug: sport_slug) || Sport.first

        # 2. Game 생성 또는 업데이트
        game = Game.find_or_initialize_by(external_id: meta["match_id"])
        game.assign_attributes(
          sport: sport,
          home_team: game_info["home_team"],
          away_team: game_info["away_team"],
          home_abbr: game_info["home_abbr"],
          away_abbr: game_info["away_abbr"],
          game_date: Time.current + 5.hours, 
          venue: game_info["venue"],
          status: "scheduled",
          league: sport_slug,
          league_name: sport_slug.upcase
        )
        game.save!

        # 3. Report 생성
        report = Report.find_or_initialize_by(game: game)
        
        # 픽 추출 로직 개선 (정규식)
        pick_match = report_text.match(/(?:최종 픽|TARGET_PICK|PICK)[:\s*]+([^\n]+)/i)
        extracted_pick = pick_match ? pick_match[1].strip.gsub(/[\*\_]/, '') : "Analytic Available"

        report.assign_attributes(
          title: "#{game.display_name} AI Intelligence Report",
          content: report_text,
          pick: extracted_pick,
          confidence: "4",
          status: "published",
          published_at: Time.current,
          structured_data: { reasoning: reasoning, raw_meta: meta }
        )
        report.save!

        puts "✅ 성공: #{game.display_name} 리포트 발행 완료"
        
        # 처리 완료 파일 이동
        FileUtils.mv(file, File.join(processed_dir, File.basename(file)))
      rescue => e
        puts "❌ 에러 발생 (#{File.basename(file)}): #{e.message}"
      end
    end
    
    puts "🎉 모든 데이터 처리가 완료되었습니다."
  end
end
