# frozen_string_literal: true

require_relative 'local_review_comment_test'

class LocalReviewBatchPublicationTest < Minitest::Test
  include LocalReviewCommentFixture

  def test_publishes_every_peer_report_and_disposition
    peers = [round, peer]
    body = render('rounds' => peers)
    assert_equal 2, body.scan('<summary>Round ').size
    assert_equal 2, body.scan('**Dispositions**').size
    assert_includes body, 'anthropic/claude'
    assert_includes body, '2 nit'
    assert body.end_with?("REVIEWED #{HEAD} BY anthropic/claude EFFORT UNKNOWN FINDINGS 1\n")
  end

  def test_clean_last_peer_does_not_hide_an_unfixed_peer_defect
    defect = round(findings: [NIT.merge('class' => 'defect')])
    clean = peer(findings: [], report: report(reviewer: 'anthropic/claude', findings: 0))
    assert_includes render('rounds' => [defect, clean]), '1 unfixed defect'
  end

  def test_same_id_on_another_reviewer_does_not_dispose_a_peer_defect
    defect = round(EARLIER, findings: [NIT.merge('class' => 'defect')])
    fixed = peer(EARLIER, findings: [NIT.merge('class' => 'defect', 'disposition' => 'fixed', 'commit' => HEAD)])
    body = render('rounds' => [defect, fixed, round(findings: [], report: report(findings: 0))])
    assert_includes body, '1 unfixed defect'
  end

  def test_final_batch_fix_requires_a_later_head_even_if_last_peer_is_clean
    fixed = round(findings: [NIT.merge('class' => 'defect', 'disposition' => 'fixed', 'commit' => EARLIER)])
    assert_raises(Shaka::Error) { render('rounds' => [fixed, peer]) }
  end

  def test_returning_to_a_previous_head_is_rejected
    assert_raises(Shaka::Error) { render('rounds' => [round, round(EARLIER), peer]) }
  end

  private

  def peer(head = HEAD, **changes)
    round(head, reviewer: 'anthropic/claude', report: report(head, reviewer: 'anthropic/claude'), **changes)
  end
end
