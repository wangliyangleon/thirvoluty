class ActivitiesController < ApplicationController
  before_filter:authenticate_user!
  helper_method :sort_column, :sort_direction

  def new
    @lucky_activity = get_lucky_activity(10, 10)
  end

  def create
    if not_participated(current_user)
      @activity = Activity.new(activity_params)
      @activity.participate_count = 1
      current_user.participate_date = Time.zone.now.to_date
      begin
        @activity.transaction do
          @activity.save
          @activity.participation_records.create(:user => current_user)
          current_user.activity_id = @activity.id
          current_user.save
        end
        flash[:success] = "Cool! Let's start Thirvolution TODAY!!!"
        redirect_to @activity
      rescue Exception => e
        flash[:alert] = e.message
        redirect_back(fallback_location: root_path)
      end
    else
      flash[:alert] = "You cannot participate multiple activities"
      redirect_to activities_url
    end
  end

  def show
    @show_user_menu = true
    fetch_current_activity_and_participation_data()
    @lucky_activity = get_lucky_activity(10, 10)
    @activity = Activity.find(params[:id])
    fetch_history_activities(10)
    @commentable = commentable(@activity)
    @activity_comments = @activity.activity_comments
  end

  def index
    @show_user_menu = true
    fetch_current_activity_and_participation_data()
    @lucky_activity = get_lucky_activity(10, 10)
    @activities = Activity.search(params[:search]).order(sort_column + " " + sort_direction)
        .paginate(:per_page => 10, :page => params[:page])
    fetch_history_activities(10)
  end

  def participate
    @current_activity = Activity.find(params[:id])
    if not_participated(current_user)
      current_user.activity_id = @current_activity.id
      current_user.participate_date = Time.zone.now.to_date
      @current_activity.increment(:participate_count, by = 1)
      begin
        @current_activity.transaction do
          @current_activity.participation_records.create(:user => current_user)
          @current_activity.save
          current_user.save
        end
        flash[:success] = "Cool! Let's start Thirvolution TODAY!!!"
      rescue Exception => e
        flash[:alert] = e.message
      end
    else
      flash[:alert] =  "You cannot participate multiple activities"
    end
    redirect_back(fallback_location: root_path)
  end

  def finish
    @current_activity = Activity.find(params[:id])
    @participated = is_participated(current_user)
    @finished = is_finished_today(current_user)
    if @participated && !@finished
      begin
        @current_activity.increment(:finish_day_count, by = 1)
        current_user.increment(:finish_day_count, by = 1)
        if (!current_user.last_finish_date.nil?) &&
            (current_user.last_finish_date == 1.days.ago.to_date)
          current_user.increment(:combo_day_count, by = 1)
        else
          current_user.combo_day_count = 1
        end
        current_user.last_finish_date = Time.zone.now.to_date

        @finish_day_count = current_user.finish_day_count
        @day_count = participate_day_count(current_user)
        if @day_count >= 30
          @is_perfectly_finished = (current_user.combo_day_count >= 30)
          if @is_perfectly_finished
            @current_activity.increment(:finish_count, by = 1)
          end
          @current_participation = @current_activity.participation_records
              .find_by(user: current_user, is_finished: false)
          if @current_participation
            @current_participation.finish_day_count = current_user.finish_day_count
            @current_participation.is_finished = true
            @current_participation.finish_time = Time.zone.now
          end

          @current_activity.transaction do
            @current_participation && @current_participation.save
            @current_activity.daily_finish_records.create(:user => current_user)
            clear_participation(current_user)
            @current_activity.save
            current_user.save
          end
          if @is_perfectly_finished
            flash[:success] = "Great! You just finished a perfect Thirvolution with #%s!!!" \
                % [@current_activity.title]
          else
            flash[:success] = "Great! You finished #%s with %d/%d days! You can do better!!!" \
                % [@current_activity.title, @finish_day_count, @day_count]
          end
        else
          @current_activity.transaction do
            @current_activity.daily_finish_records.create(:user => current_user)
            @current_activity.save
            current_user.save
          end
          flash[:success] = "Cool! Let's continue tomorrow!!!"
        end
      rescue Exception => e
        flash[:alert] = e.message
      end
    elsif @finished
      flash[:alert] =  "You have finished today's activity"
    else
      flash[:alert] =  "Please join an activity first"
    end
    redirect_back(fallback_location: root_path)
  end

  def comment
    @current_activity = Activity.find(params[:id])
    if commentable(@current_activity)
      @current_activity.activity_comments.create(:user => current_user,
          :content => params[:activity_comment][:content])
    else
      flash[:alert] =  "You can only comment on the activities you used to participate"
    end
    redirect_back(fallback_location: root_path)
  end

  private
  def activity_params
    params.required(:activity).permit(:title)
  end

  def sort_column
    Activity.column_names.include?(params[:sort]) ? params[:sort] : "updated_at"
  end

  def sort_direction
    %w[asc desc].include?(params[:direction]) ? params[:direction] : "desc"
  end

  def fetch_current_activity_and_participation_data
    @is_participated = is_participated(current_user)
    @day_count = 0
    if @is_participated
      @current_activity = Activity.find(current_user.activity_id)
      @is_finished_today = is_finished_today(current_user)
      @day_count = participate_day_count(current_user)
      @day_count_from_finish = 30 - @day_count + 1
    end
  end

  def fetch_history_activities(limit)
    @history_activities = get_history_activities(current_user)
    @is_show_all_link = @history_activities.count > limit
    @history_activities_to_show = @history_activities[0...limit]
  end

  def get_lucky_activity(new_candidate_number, hot_candidate_number)
    activity_candidates_new = Activity.order('created_at DESC').limit(new_candidate_number).to_a
    activity_candidates_hot = Activity.order('participate_count DESC').limit(hot_candidate_number).to_a
    activity_candidates_new.concat(activity_candidates_hot).shuffle[0]
  end

  def commentable(activity)
    current_user.participation_records.find_by(activity: activity) != nil
  end

end
