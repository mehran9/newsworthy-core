class MentionToMentionIndustry
  include ParseModel

  index({ Hiddern: 1 }, { background: true })
  index({ _p_Mention: 1, _p_RelatedMention: 1, _p_Industry: 1 }, { background: true, unique: true })
end
