module ApplicationHelper
  def display_number(count, max)
    class_text = 'rounded-div'
    class_text += ' achieved-goal-no' if count >= max
    class_text += ' rounded-div-last' if max == 50
    "<div class=\"#{class_text}\">#{max}</div>".html_safe
  end

  def display_text(count, max, num)
    class_text = ''
    class_text = 'achieved-goal-type' if count >= max
    "<h7 class=\"#{class_text}\">#{num}</h7>".html_safe
  end
end
