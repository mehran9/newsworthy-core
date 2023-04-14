class MentionToMention
  include ParseModel

  index({ _p_Mention: 1, _p_RelatedMention: 1 }, { background: true, unique: true })
  index({ Hiddern: 1 }, { background: true })
end
