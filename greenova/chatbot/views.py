from django.shortcuts import render, redirect, get_object_or_404
from django.contrib.auth.decorators import login_required
from django.http import JsonResponse, HttpResponse
from django.views.decorators.http import require_POST
from django.views.decorators.csrf import csrf_exempt
from django.conf import settings
from django.utils.html import escape

from .models import Conversation, ChatMessage
from .services import ChatbotService
from .forms import ConversationForm

import json
import logging

logger = logging.getLogger(__name__)

@login_required
def chatbot_home(request):
    """Main chatbot interface showing conversation list and a selected conversation."""
    user = request.user
    conversations = Conversation.objects.filter(user=user).order_by('-updated_at')

    active_conversation_id = request.GET.get('conversation_id')
    active_conversation = None
    messages = []

    if active_conversation_id:
        active_conversation = get_object_or_404(Conversation, id=active_conversation_id, user=user)
        messages = ChatMessage.objects.filter(conversation=active_conversation).order_by('timestamp')

    context = {
        'conversations': conversations,
        'active_conversation': active_conversation,
        'messages': messages,
    }

    return render(request, 'chatbot/home.html', context)

@login_required
def create_conversation(request):
    """Create a new conversation."""
    if request.method == 'POST':
        form = ConversationForm(request.POST)
        if form.is_valid():
            conversation = form.save(commit=False)
            conversation.user = request.user
            conversation.save()

            # Add initial bot greeting
            ChatbotService.add_message(
                conversation_id=conversation.id,
                content="Hello! How can I help you today?",
                is_bot=True
            )

            return redirect('chatbot:chatbot_home', conversation_id=conversation.id)
    else:
        form = ConversationForm()

    return render(request, 'chatbot/create_conversation.html', {'form': form})

@login_required
def conversation_detail(request, conversation_id):
    """View a specific conversation."""
    conversation = get_object_or_404(Conversation, id=conversation_id, user=request.user)
    messages = ChatMessage.objects.filter(conversation=conversation).order_by('timestamp')

    return render(request, 'chatbot/conversation_detail.html', {
        'conversation': conversation,
        'messages': messages,
    })

@login_required
@require_POST
def send_message(request, conversation_id):
    """Process a new message in a conversation."""
    conversation = get_object_or_404(Conversation, id=conversation_id, user=request.user)

    try:
        data = json.loads(request.body)
        message_text = data.get('message', '').strip()

        if not message_text:
            return JsonResponse({'error': 'Message cannot be empty'}, status=400)

        # Save user message
        user_message = ChatbotService.add_message(
            conversation_id=conversation.id,
            content=message_text,
            is_bot=False
        )

        # Process and get bot response
        bot_response = ChatbotService.process_user_message(conversation.id, message_text)

        return JsonResponse({
            'user_message': {
                'id': user_message.id,
                'content': escape(user_message.content),
                'timestamp': user_message.timestamp.isoformat(),
            },
            'bot_response': {
                'content': escape(bot_response),
            }
        })
    except Exception as e:
        logger.error(f"Error processing message: {str(e)}")
        return JsonResponse({'error': 'Failed to process message'}, status=500)

@login_required
def delete_conversation(request, conversation_id):
    """Delete a conversation."""
    conversation = get_object_or_404(Conversation, id=conversation_id, user=request.user)

    if request.method == 'POST':
        conversation.delete()
        return redirect('chatbot:chatbot_home')

    return render(request, 'chatbot/delete_conversation.html', {'conversation': conversation})
